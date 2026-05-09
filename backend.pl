#!/usr/local/ActivePerl-5.14/site/bin/morbo

# HPO Backend 08.03.2017 by Daniel Boehringer

use Mojolicious::Lite;
use Mojolicious::Plugin::Database;
use SQL::Abstract;
use SQL::Abstract::More;
use Data::Dumper;
use Mojo::UserAgent;
use Apache::Session::File;
use Encode;
use Mojo::JSON qw(decode_json encode_json);
use DBIx::Connector;
use POSIX qw(strftime);

no warnings 'uninitialized';

helper connector_db => sub {
    state $db = DBIx::Connector->new('dbi:Pg:dbname=hpo;host=localhost', 'postgres','postgres',  { pg_enable_utf8 => 1, AutoCommit => 1 });
};
helper db => sub { shift->connector_db->dbh };


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
    my $name_only = $self->param('nameOnly') || '0'; # Read NameOnly flag (default: 0)

    my $base_where;
    my @bind_params;

    # NEU: Prüfen, ob die Suchanfrage das Format HP:1234567 hat (case-insensitive)
    if ($query =~ /^hp:0*(\d+)$/i) {
        my $numeric_id = $1; # Führende Nullen werden durch 0* ignoriert
        $base_where = "WHERE t.id = ?";
        @bind_params = ($numeric_id);
    } 
    else {
        # Bisheriges Verhalten: Normale Textsuche mit Wildcards
        my $search_term = "%$query%";
        $base_where = "WHERE t.label ILIKE ?";
        @bind_params = ($search_term);

        # Wenn "Name Only" aus ist, in Definitionen und Synonymen mitsuchen
        if ($name_only eq 'false' || $name_only eq '0') {
            $base_where = "WHERE t.label ILIKE ? OR t.definition ILIKE ? OR EXISTS (SELECT 1 FROM public.synonyms s WHERE s.idterm = t.id AND s.label ILIKE ?)";
            push @bind_params, $search_term, $search_term;
        }
    }

    # HPO is a DAG. We resolve exactly ONE valid path towards the root for each hit.
    my $sql = qq{
                    WITH RECURSIVE search_tree AS (
                    -- Basis: Find matching HPO terms
                    SELECT t.id as match_id, t.id as current_id, ARRAY[t.id] as path
                    FROM public.terms t
                    $base_where

                    UNION ALL

                    -- Recursion: Walk upwards to the root
                    SELECT st.match_id, i.idparent as current_id, i.idparent || st.path
                    FROM search_tree st
                    JOIN public.isas i ON st.current_id = i.idchild
                    )
                    -- For every matched ID, take just the longest single path back to the root
                    SELECT DISTINCT ON (match_id) match_id, path
                    FROM search_tree
                    ORDER BY match_id, array_length(path, 1) DESC
                };

    my $sth = $self->db->prepare($sql);
    $sth->execute(@bind_params);

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
                    SELECT t.id, t.label, t.definition,
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
                    SELECT t.id, t.label,  t.definition,
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

    my $sql=qq{ select distinct terms.id, terms.label, terms.definition from all_childen_of(?) a join terms on terms.id = a.identity };
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


# Allow ENV override, fallback to localhost
my $VECTORSTORE_BASE_URL = $ENV{VECTORSTORE_URL} // 'http://localhost:3036';

# ==========================================
# GLOBAL CONFIG CONSTANTS
# ==========================================
use constant {
    LLM_PHENOTYPE_EXTRACTION_PROMPT_ID   => 50, # Prompt ID für die initiale Extraktion
    LLM_HPO_RETRIEVAL_PROMPT_ID          => 51, # Standard HPO Vectorstore (Phänotypen, Onset, Severity)
    LLM_HPO_MODIFIER_RETRIEVAL_PROMPT_ID => 52, # NEU: Separater Vectorstore für Modifiers
};

# Disable Keep-Alive caching for massive parallel requests
my $ua = Mojo::UserAgent->new(request_timeout => 0, inactivity_timeout => 0, connect_timeout => 0);
$ua->max_connections(0);

# =========================================================
# HELPER: ID Formatierung
# Macht aus "1558" ein "HP:0001558"
# =========================================================
helper format_hpo_id => sub {
    my ($self, $raw_id) = @_;

    # Entferne evtl. vorhandene Leerzeichen oder Text, behalte nur Ziffern
    $raw_id =~ s/\D//g;

    # Fallback auf 118 (HP:0000118 = Phenotypic abnormality), falls leer
    $raw_id = 118 unless $raw_id;

    # Fülle mit führenden Nullen auf 7 Stellen auf und setze "HP:" davor
    return sprintf("HP:%07d", $raw_id);
};

# =========================================================
# HELPER: Map Natural Text to HPO via Dense Retrieval
# Returns a Mojo::Promise resolving to { id => '...', label => '...' }
# =========================================================
helper map_to_hpo_async => sub {
    my ($self, $term, $is_modifier) = @_;

    return Mojo::Promise->resolve(undef) unless $term;

    # Wähle den korrekten Prompt/Vectorstore basierend auf dem Flag
    my $prompt_id = $is_modifier ? LLM_HPO_MODIFIER_RETRIEVAL_PROMPT_ID : LLM_HPO_RETRIEVAL_PROMPT_ID;
    my $url_retrieve = "$VECTORSTORE_BASE_URL/LLM/run_stateless/" . $prompt_id;

    return $ua->post_p($url_retrieve => {Accept => '*/*'} => encode('UTF-8', $term))->then(sub {
        my $tx = shift;
        if ($tx->result && $tx->result->is_success) {

            my $matches = eval { decode_json($tx->result->body) } // [ ];

            # Vectorstore returns:[{"id": "1558", "label": "Mapped Term"}, ...]
            if (ref $matches eq 'ARRAY' && @$matches && defined $matches->[0]->{label}) {

                # Formatierung der nackten ID in eine valide HP-ID
                my $formatted_id = $self->format_hpo_id($matches->[0]->{label});
                return {
                    id    => $formatted_id,
                    label => $matches->[0]->{payload} // $term
                };
            }
        }
        # Fallback if no specific match is found
        return { id => "HP:0000118", label => $term };
    })->catch(sub {
        my $err = shift;
        app->log->warn("Vectorstore retrieval failed for '$term': $err");
        return { id => "HP:0000118", label => $term };
    });
};

# =========================================================
# ROUTE: Generate Phenopacket from Medical Report
# =========================================================
post '/DBB/extract_phenopacket' => sub {
    my $c = shift;

    # 1. Read input text
    my $payload = $c->req->json;
    my $text_content = $payload->{medical_report} // $payload->{report} // '';

    unless ($text_content) {
        return $c->render(json => { error => "Missing 'medical_report' in JSON body" }, status => 400);
    }

    my $url_extract = "$VECTORSTORE_BASE_URL/LLM/run_stateless/" . LLM_PHENOTYPE_EXTRACTION_PROMPT_ID;

    # 2. Call Extraction LLM
    $c->render_later;
    $ua->post_p($url_extract => {Accept => '*/*'} => encode('UTF-8', $text_content))->then(sub {
        my $tx_extract = shift;

        unless ($tx_extract->result && $tx_extract->result->is_success) {
            die "Extraction LLM Failed: " . ($tx_extract->result ? $tx_extract->result->message : 'Unknown Error');
        }

        # Parse extracted JSON
        my $extracted_data = eval { decode_json($tx_extract->result->body) } // { };
        my $raw_features = $extracted_data->{phenotypicFeatures} // [ ];

        # 3. Dense Retrieval Mapping (Concurrent)
        my @feature_promises;

        foreach my $raw_feat (@$raw_features) {
            next unless $raw_feat->{type} && $raw_feat->{type}{label};

            # Map the core Type (is_modifier = 0)
            my $feat_promise = $c->map_to_hpo_async($raw_feat->{type}{label}, 0)->then(sub {
                my $mapped_type = shift;
                my $mapped_feature = { type => $mapped_type };

                my @sub_promises;

                # Map Severity (is_modifier = 1)
                if (my $sev_label = $raw_feat->{severity}{label}) {
                    push @sub_promises, $c->map_to_hpo_async($sev_label, 1)->then(sub {
                        $mapped_feature->{severity} = shift;
                    });
                }

                # Map Onset (is_modifier = 1)
                if (my $ons_label = $raw_feat->{onset}{ontologyClass}{label}) {
                    push @sub_promises, $c->map_to_hpo_async($ons_label, 1)->then(sub {
                        $mapped_feature->{onset} = { ontologyClass => shift };
                    });
                }

                # Map other Modifiers (is_modifier = 1)
                if (my $mods = $raw_feat->{modifiers}) {
                    $mapped_feature->{modifiers} =[];
                    foreach my $mod (@$mods) {
                        if (my $mod_label = $mod->{label}) {
                            push @sub_promises, $c->map_to_hpo_async($mod_label, 1)->then(sub {
                                push @{$mapped_feature->{modifiers}}, shift;
                            });
                        }
                    }
                }

                # Filter undefined entries to prevent "clone on undefined value" in Mojo::Promise
                @sub_promises = grep { defined $_ } @sub_promises;

                # Wait for all sub-attributes to resolve (Skip if empty)
                if (@sub_promises) {
                    return Mojo::Promise->all(@sub_promises)->then(sub {
                        return $mapped_feature;
                    });
                } else {
                    return Mojo::Promise->resolve($mapped_feature);
                }
            });

            push @feature_promises, $feat_promise;
        }

        # Filter undefined entries to prevent "clone on undefined value"
        @feature_promises = grep { defined $_ } @feature_promises;

        if (!@feature_promises) {
            return $c->render(json => { error => "No phenotypic features extracted." }, status => 400);
        }

        # 4. Wait for ALL feature mapping to complete
        return Mojo::Promise->all(@feature_promises)->then(sub {
            my @final_features = map { $_->[0] } @_;

            # 5. Assemble final Phenopacket schema 2.0 object
            my $timestamp = strftime("%Y-%m-%dT%H:%M:%SZ", gmtime);

            my $phenopacket = {
                id => "phenopacket-" . time(),
                subject => {
                    id => "anonymous-patient",
                    taxonomy => {
                        id => "NCBITaxon:9606",
                        label => "homo sapiens"
                    }
                },
                phenotypicFeatures => \@final_features,
                metaData => {
                    created => $timestamp,
                    createdBy => "OntoMan",
                    phenopacketSchemaVersion => "2.0.0",
                    resources =>[
                    {
                        id => "hp",
                        name => "human phenotype ontology",
                        url => "http://purl.obolibrary.org/obo/hp.owl",
                        version => "2023-10-09",
                        namespacePrefix => "HP",
                        iriPrefix => "http://purl.obolibrary.org/obo/HP_"
                    }
                    ]
                }
            };

            $c->render(json => $phenopacket);

        });

    })->catch(sub {
        my $err = shift;
        $c->app->log->error("Error during Phenopacket Generation: $err");
        $c->render(json => { error => "Pipeline failed", details => "$err" }, status => 500);
    });
};



###################################################################
# main()

app->config(hypnotoad => {listen => ['http://*:3026'], workers => 3, heartbeat_timeout=>120, inactivity_timeout=> 120});
app->start;
