#!/usr/local/ActivePerl-5.14/site/bin/morbo

# HPO Backend 08.03.2017 by Daniel Boehringer

use Mojolicious::Lite;
use Mojolicious::Plugin::Database;
use SQL::Abstract;
use SQL::Abstract::More;
use Data::Dumper;
use Mojo::UserAgent;
use Apache::Session::File;
use Mojolicious::Plugin::RenderFile;
use Encode;
use Mojo::JSON qw(decode_json encode_json);
use DBIx::Connector;

no warnings 'uninitialized';


helper connector_db => sub {
    state $db = DBIx::Connector->new('dbi:Pg:dbname=hpo;host=localhost', 'postgres','postgres',  { pg_enable_utf8 => 1, AutoCommit => 1 });
};
helper db => sub { shift->connector_db->dbh };


plugin 'RenderFile';

# turn browser cache off
hook after_dispatch => sub {
    my $tx = shift;
    my $e  = Mojo::Date->new(time - 100);
    $tx->res->headers->header(Expires => $e);
    $tx->res->headers->header('X-ARGOS-Routing' => '3026');
};

get '/DBB/hpo/search/:query' => sub {
    my $self = shift;
    my $query = $self->param('query');
    my $search_term = "%$query%";

    # HPO ist ein DAG. Wir bauen das Array Schritt für Schritt auf
    # und nehmen am Ende nur EINEN validen Pfad pro Treffer.
    my $sql = q{
                    WITH RECURSIVE search_tree AS (
                    -- Basis: Finde die passenden HPO Terms. Wir starten das Array mit dem Treffer.
                    SELECT t.id as match_id, t.id as current_id, ARRAY[t.id] as path
                    FROM public.terms t
                    WHERE t.label ILIKE ?

                    UNION ALL

                    -- Rekursion: Finde die Eltern-Knoten und setze sie VOR den bisherigen Pfad (|| Operator)
                    SELECT st.match_id, i.idparent as current_id, i.idparent || st.path
                    FROM search_tree st
                    JOIN public.isas i ON st.current_id = i.idchild
                    -- Optionaler Zirkelbezug-Schutz: WHERE NOT i.idparent = ANY(st.path)
                    )
                    -- DISTINCT ON (match_id) wählt für jeden Treffer exakt EINEN Pfad aus.
                    -- ORDER BY array_length stellt sicher, dass wir den längsten Pfad nehmen (der bis ganz zur Wurzel reicht).
                    SELECT DISTINCT ON (match_id) match_id, path
                    FROM search_tree
                    ORDER BY match_id, array_length(path, 1) DESC
                };

    my $sth = $self->db->prepare($sql);
    $sth->execute($search_term);

    my $results = $sth->fetchall_arrayref({});

    foreach my $row (@$results) {
        if ($row->{path} =~ /^\{(.*)\}$/) {
            my @path_array = split(',', $1);
            $row->{path} = \@path_array;
        }
    }

    $self->render(json => $results);
};

###########################################
# generic dbi part

helper fetchFromTable => sub { my ($self, $table, $sessionid, $where)=@_;
    my $sql = SQL::Abstract::More->new;
    my $order_by=[];

    my @a;

    if (1|| $sessionid)        # implement session-bound serverside security
    {
        $table = 'thai_filtered' if $table eq 'thai_project';
        my @cols=qw/*/;
        my($stmt, @bind) = $sql->select( -columns  => [-distinct => @cols], -from => $table, -where=> $where, -order_by=> $order_by);
        my $sth = $self->db->prepare($stmt);
        $sth->execute(@bind);

        return $sth->fetchall_arrayref({});
    }

    return [];
};

# Fetch root nodes (nodes with no parents)
get '/DBB/hpo/roots' => sub {
    my $self = shift;
    my $sql = q{
                    SELECT t.id, t.label,
                    (CASE WHEN EXISTS (SELECT 1 FROM public.isas WHERE idparent = t.id) THEN 0 ELSE 1 END) as is_leaf
                    FROM public.terms t
                    WHERE t.id in (SELECT idparent FROM public.isas )
                    order by 2
                };
    my $sth = $self->db->prepare($sql);
    $sth->execute();
    
    $self->render(json => $sth->fetchall_arrayref({}));
};

# Fetch children of a specific node
get '/DBB/hpo/children/:id' => [id => qr/.+/] => sub {
    my $self = shift;
    my $id = $self->param('id');
    my $sql = q{
                    SELECT t.id, t.label,
                           (CASE WHEN EXISTS (SELECT 1 FROM public.isas WHERE idparent = t.id) THEN 0 ELSE 1 END) as is_leaf
                    FROM public.terms t
                    JOIN public.isas i ON t.id = i.idchild
                    WHERE i.idparent = ?
                    ORDER BY t.label
                };
    my $sth = $self->db->prepare($sql);
    $sth->execute($id);
    
    $self->render(json => $sth->fetchall_arrayref({}));
};

get '/DBB/children/idparent/:pk' => [pk=>qr/[0-9]+/] => sub
{    my $self = shift;
    my $pk  = $self->param('pk');

    my $sql=qq{ select distinct terms.id, terms.label from all_childen_of(?) a join terms on terms.id = a.identity };
    my $sth = $self->db->prepare( $sql );
    $sth->execute(($pk));

    $self-> render(json => $sth->fetchall_arrayref({}));
};

# Fetch synonyms for a specific node
get '/DBB/hpo/synonyms/:id' => [id => qr/.+/] => sub {
    my $self = shift;
    my $id = $self->param('id');
    my $sql = q{ SELECT distinct idterm, label FROM public.synonyms WHERE idterm = ? ORDER BY label };
    my $sth = $self->db->prepare($sql);
    $sth->execute($id);

    $self->render(json => $sth->fetchall_arrayref({}));
};

# Fetch xrefs for a specific node
get '/DBB/hpo/xrefs/:id' => [id => qr/.+/] => sub {
    my $self = shift;
    my $id = $self->param('id');
    my $sql = q{
                    SELECT distinct idterm, label
                    FROM public.xrefs
                    WHERE idterm = ?
                    AND label NOT LIKE 'property_value%'
                    AND label NOT LIKE 'created_by%'
                    AND label NOT LIKE 'terms:%'
                    ORDER BY label
                };
    my $sth = $self->db->prepare($sql);
    $sth->execute($id);

    $self->render(json => $sth->fetchall_arrayref({}));
};

# fetch all entities
get '/DBB/:table'=> sub
{
    my $self = shift;
    my $table  = $self->param('table');
    my $sessionid  = $self->param('session');

    my $res = $self->fetchFromTable($table, $sessionid, {});

    $self-> render( json => $res);
};

# fetch entities by (foreign) key
get '/DBB/:table/:col/:pk' => [col=>qr/[a-z_0-9\s]+/, pk=>qr/[a-z0-9\s\-_\.]+/i] => sub
{
    my $self = shift;
    my $table  = $self->param('table');
    my $pk  = $self->param('pk');
    my $col  = $self->param('col');
    my $sessionid  = $self->param('session');
    my $res=$self->fetchFromTable($table, $sessionid, {$col=> $pk});

    $self->render( json => $res);
};

# update
put '/DBB/:table/:pk/:key'=> [key=>qr/\d+/] => sub
{
    my $self    = shift;
    my $table    = $self->param('table');
    my $pk        = $self->param('pk');
    my $key        = $self->param('key');
    my $sql        = SQL::Abstract->new;

    my $ret;
    app->log->debug();
    if($table ne 'documents' && $self->req->body) {
        my $jsonR   = decode_json( $self->req->body || '{}');
        my($stmt, @bind) = $sql->update($table, $jsonR, {$pk=>$key});
        my $sth = $self->db->prepare($stmt);
        $sth->execute(@bind);
        app->log->debug("err: ".$DBI::errstr ) if $DBI::errstr;
        $ret={err=> $DBI::errstr};
    }
    $self->render( json=> $ret);
};

# insert
post '/DBB/:table/:pk'=> sub
{
    my $self    = shift;
    my $table    = $self->param('table');
    my $pk        = $self->param('pk');
    my $sql = SQL::Abstract->new;
    my $jsonR   = decode_json( $self->req->body  || '{"name":"New"}' );

    my($stmt, @bind) = $sql->insert( $table, $jsonR);
    my $sth = $self->db->prepare($stmt);
    $sth->execute(@bind);
    app->log->debug("err: ".$DBI::errstr ) if $DBI::errstr;
    my $valpk= $self->db->last_insert_id(undef, undef, $table, $pk);

    $self->render( json=>{err=> $DBI::errstr, pk => $valpk} );
};

# delete
del '/DBB/:table/:pk/:key'=> [key=>qr/\d+/] => sub
{
    my $self    = shift;
    my $table    = $self->param('table');
    my $pk        = $self->param('pk');
    my $key        = $self->param('key');
    my $sql = SQL::Abstract->new;

    my($stmt, @bind) = $sql->delete($table, {$pk=>$key});
    my $sth = $self->db->prepare($stmt);
    $sth->execute(@bind);
    app->log->debug("err: ".$DBI::errstr ) if $DBI::errstr;
    
    $self->render( json=>{err=> $DBI::errstr} );
};

###################################################################
# main()

app->config(hypnotoad => {listen => ['http://*:3026'], workers => 3, heartbeat_timeout=>120, inactivity_timeout=> 120});
app->start;
