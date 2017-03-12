#!/usr/local/ActivePerl-5.14/site/bin/morbo

# NLP Backend 08.03.2017 by Daniel Boehringer

# todos:
#       support bcc mode

use Mojolicious::Lite;
use Mojolicious::Plugin::Database;
use SQL::Abstract::More;
use Data::Dumper;
use Mojo::UserAgent;
use Apache::Session::File;
use Mojolicious::Plugin::RenderFile;
use Encode;
use Mojo::JSON qw(decode_json encode_json);

no warnings 'uninitialized';

plugin 'database', {
        databases => {
            db=>{
                dsn	  => 'dbi:Pg:dbname=nlp;host=localhost',
                username => 'postgres',
                password => 'postgres',
                options  => { 'pg_enable_utf8' => 1, AutoCommit => 1 },
                helper   => 'db'
            }
        }
};
plugin 'RenderFile'; 


helper preprocess_text => sub { my ($self, $text)=@_;
    $text =~s/<c3><84>/Ä/ogsi;
    $text =~s/<c3><bc>/ü/ogsi;
    $text =~s/<c3><a4>/ä/ogsi;
    $text =~s/<c3><b6>/ö/ogsi;
    $text =~s/<c3><9f>/ß/ogsi;
    $text =~s/<c3><a8>/è/ogsi;
    $text =~s/<c3><96>/Ö/ogsi;

    $text =~s/<..>(.)<...>/$1/ogsi;
    $text =~s/<[^>]+>Z\.n<[^>]+>\s+\.\s+/<TIATTR> Zustand nach <\/TIATTR>/ogsi;
    $text =~s/<[^>]+>Z\.<[^>]+>\s+<[^>]+>n<[^>]+>\s+\./<TIATTR> Zustand nach <\/TIATTR>/ogsi;
    $text =~s/<NE>Aktuell<\/NE>\s+:/<TIATTR> Aktuell <\/TIATTR>/ogsi;
    $text =~s/<[^>]+>V\.a<[^>]+>\s+\.\s+/<CERTAINTY> Verdacht auf <\/CERTAINTY>/ogsi;
    $text =~s/<[^>]+>V\.<[^>]+>\s+a\s+\.s+/<CERTAINTY> Verdacht auf <\/CERTAINTY>/ogsi;
    $text =~s/<[^>]+>a\.e<[^>]+>\s+\.\s+/<CERTAINTY> Am ehesten <\/CERTAINTY>/ogsi;

    $text =~s/<CARD>[0-9]{5}<\/CARD>\s+<N.>([^>]+)<\/N.>/<ORT>$1<\/ORT>/ogsi;
    $text =~s/<[^>]+>([^>]+?(str|strasse|straße|platz|weg))<\/[^>]+>[\s\.]*<CARD>([^>]+?)<\/CARD>/<STR>$1 $3<\/STR>/ogsi;
    $text =~s/<CARD>(0761[^>]+?)<\/CARD>/<TEL>$1 $2<\/TEL>/ogsi;
    $text =~s/<[^>]+>(kolleg[^>]+|FRAU|HERR[N]?)<[^>]+>/<ANREDE>$1<\/ANREDE>/ogsi;
    $text =~s/<[^>]+>((Prof|Dr|med[\.]?)[^>]*)<[^>]+>[\s\.]*/<PTITLE>$1<\/PTITLE>/ogsi;

    $text =~s/<N.>([BRL]A)<\/N.>/<LOC>$1<\/LOC>/ogsi;
    $text =~s/<[^>]+>rechte[snm]<[^>]+>\s+<[^>]+>Aug[esn]+<[^>]+>/<LOC>RA<\/LOC>/ogsi;
    $text =~s/<[^>]+>linke[snm]<[^>]+>\s+<[^>]+>Aug[esn]+<[^>]+>/<LOC>LA<\/LOC>/ogsi;
    $text =~s/<[^>]+>beide[n]?<[^>]+>\s+<[^>]+>Augen<[^>]+>/<LOC>BA<\/LOC>/ogsi;
    $text =~s/<[^>]+>(beidseits|beids\.?|bds\.?)<[^>]+>/<LOC>BA<\/LOC>/ogsi;
    $text =~s/<[^>]+>(r(.)l)<[^>]+>/<LOC>BA<\/LOC>/ogsi;
    $text =~s/<[^>]+>(rechts)<[^>]+>/<LOC>RA<\/LOC>/ogsi;
    $text =~s/<[^>]+>(links)<[^>]+>/<LOC>LA<\/LOC>/ogsi;
    $text =~s/<[^>]+>([kk]ornea|hh|fd|wirts[^>]+|^ora|hornhaut|linke|iris|pupille|vorderkammer|vk|papille|sehner[^>]+|ma[ck]ula|fovea|netzhaut|kammerwinkel|kw|zonula|arkade|limbus|epithel|stroma|endothel|pigmentepithel|bündel|senke|peripherie|[^>]+rand|[^>]+zentrum|[^>]+randraum|iol|intraokularl[^>]|nervenfaser[^>]+|bindehaut|transplantat|^tp[l\.]*|[ck]onjun[ck]t[^>]+|areal[e]?|medien|bereich)<[^>]+>/<ANATOM>$1<\/ANATOM>/ogsi;
    $text =~s/<[^>]+>([^>]+(aris|ilis|atus|ilata|amatus|ectus|ecta|piens|führend))<[^>]+>/<ADJA>$1<\/ADJA>/ogsi;
    $text =~s/<[^>]+>(o[ck]+ult[ernm]+|multipl[ernms]+|vital[ersmn]+|stumpf[ersmn]+|randscharf[ersmn]+|mild[ersmn]+|reizfrei[ersmn]+|reizarm[ersmn]+|leer[ersmn]+|feucht[ersmn]+|trock[ersmn]+|[^>]+ient|nasal|temporal|viel[ersmn]+|wenig[ersmn]+|anliegend[ersmn]+|gestaucht[ersmn]+|gestippt[ersmn]+|schlecht[ersmn]+|bess[ersmn]+|sicca|atö[ersmn]+)<[^>]+>/<ADJA>$1<\/ADJA>/ogsi;
    $text =~s/<[NF].>([^>]+verschluss|[ck]atara[^>]+|[^>]*amotio[^>]*|[^>]*ablösun[gen]+|[^>]*itis|[^>]*ose|[^>]*generation|amd|cmv|CCS|smd[^>]*vaskularisation|morbus[^>]|[^>]*ödem|[^>]*dekompensation|[^>]+befund|[^>]*un[gen]+|[^>]*erkrankun[gen]+|[^>]*störun[gen]+|[^>]*ul[kcusera]+|[^>]*zündun[gen]+|[^>]*schielen|[^>]*opie|[^>]*mus|[^>]*star|[^>]*opie|[^>]*narbe|[^>]*iom|[^>]*gium|[^>]*cula|[^>]*phakie|[^>]*tion|[^>]*tio[en]+|[^>]*ophie|[^>]*tonie|[^>]*athie|[^>]*kom|[^>]*ämie|[^>]*ression|[^>]*nom|[^>]*giom|[^>]*foram[ensia]+|[^>]*osis|[^>]*osie|[^>]*nävus|[^>]*-riss|POWG|PCOWG|[^>]*illom|[^>]*iasie[n]?|[^>]*konus|[^>]*globus|[^>]*pathi[ea]|[^>]*syndrom|[^>]*response|[^>]-schub|[^>]chie[n]?|[^>]*skotom[e]?|VAV|CNV|[^>]*reaktio[en]+|[^>]*lys[en]+|[^>]*sis|[^>]*omie|[^>]*keit|[^>]*kung|[^>]+-Ca|[^>]+phom|[^>]+olie[^>]+vus|[^>]+nävi|[^>]+igung|[^>]+sfall|[^>]+plex|MS|[^>]sion|[^>]malie|[^>]malazie|[^>]osi[ones]+|[^>]plasie|pex|[^>]*zion|[^>]*olum|[^>]*chstand|[^>]*iefstand|rop|[^>]*stom|adhs|[^>]*loch|[^>]*infarkt|[^>]*penie|[^>]*zytose[^>]*areale|Telangiektasien|[^>]pathie|[^>]ckage)<\/[NF].>/<DIAG>$1<\/DIAG>/ogsi;
    $text =~s/<[^>]+>cornea<[^>]+>\s+<[^>]+>guttata<[^>]+>/<DIAG>Cornea guttata<\/DIAG>/ogsi;
    $text =~s/<[^>]+>diabetes<[^>]+>\s+<[^>]+>mellitus<[^>]+>/<DIAG>Diabetes mellitus<\/DIAG>/ogsi;
    $text =~s/<[^>]+>multiple<[^>]+>\s+<[^>]+>sklerose<[^>]+>/<DIAG>Multiple sklerose<\/DIAG>/ogsi;
    $text =~s/<[^>]+>morbus<[^>]+>\s+<[^>]+>(<[^>]+)>/<DIAG>$1<\/DIAG>/ogsi;
    $text =~s/<[^>]+>(art|arterielle|a)<[^>]+>\s+\.?\s*<[^>]+>hypertonie<[^>]+>/<DIAG>Bluthochdruck<\/DIAG>/ogsi;

    $text =~s/<[^>]+>(vorgeschichte|beurteilung|epikrise||befund[e]?|operation|allgemein)<[^>]+>\s+:/\n\n<STRUCTURE>$1<\/STRUCTURE>\n/ogsi;
    $text =~s/<[^>]+>(allgemein|befund[e]?|diagnose[n]?|beurteilung|VAA|fachbereich|vorgeschichte)<[^>]+>[\s:]+/\n\n<STRUCTURE>$1<\/STRUCTURE>\n/ogsi;
    $text =~s/<[^>]+>(EYLEA[^>]*|fotil|dotrav|trusopt|clonid|mitomycin|azopt|avastin|lucentis|[^>]+olol|Timophtal|valtrex|aciclovir|floxal|vori[ck]onazol|vexol|inflanefran[^>]*|dexa[^>]*|xalatan|travatan|Mar[ck]umar|plavix|xarelto|metformin|ciclosporin|decortin|prednisolon|amiodaron|Tamsulosin|Penicillin|Cefuroxim|ganfort|Triamcinolon|lumigan|Metothrexat|[^>]+azol[^>]+|ASS|glaupax|acemit|diamox|sandimmun|myfortic)<[^>]+>/<MED>$1<\/MED>/ogsi;
    $text =~s/<[^>]+>([^>]+)<[^>]+>\s*<[^>]+>AT<[^>]+>/<MED>$1<\/MED>/ogsi;
    $text =~s/<[^>]+>(visus|tensio|augendruck|OCT|pentacam|orbscan|amsler|augenstellung|doppelbildschema)<[^>]+>/\n<MEASURE>$1<\/MEASURE>/ogsi;

    $text =~s/<[^>]+>([^>]*infiltra[ten]+|pitat[en]+|blutung[en]+|narb[en]+|ung[en]|enz[en]+|[^>]*zellen|lichtweg|[^>]*atrophie|reflexe|doppelbilder|[^>]+herde|exsudat[ens]+|[^>]+areal|prominenz|pigment)<[^>]+>/<BEFUND>$1<\/BEFUND>/ogsi;

    $text =~s/\s+\.\s+/.<BREAK>\n<\/BREAK>/ogsi;
    # $text =~s/\s+([,])\s+/$1<BREAK> /ogsi;
    $text =~s/\s+([:,])\s+/$1 /ogsi;
    $text =~s/\n\s+/\n/ogsi;
    $text =~s/<(.?)ADJ.>/<$1ADJ>/ogsi;  # treat all adjectives the same
    return $text;
};

helper extract_entities => sub { my ($self, $pk, $text, $query, $name, $idletter, $res)=@_;
    my $content_array = [];
    sub _extract_entities{
        my $key = shift;
        my $value = shift;
        my $out = shift;
        my $pk = shift;
        state $i = 0;
        push @$out, {id=>$i, idletter => $pk, name => $key, content => $value} if $key!~/ART|KON|STRUCTURE|APPR|PPER/ && $value!~/^.?\s*$|^untersuchung|^Durchführung|Vorstellung|^Operation|^XX+|^\/.+/ios;
        $i++;
        return '';
    }
    $text =~s/<([^>]+)>\s*([^<]+)<[^>]+>\s*/_extract_entities($1, $2, $content_array, $pk)/gsei;
    # this is a mini-grammar on the entity-names that supports full regex-syntax (e.g. 'LOC* TIATTR* CERTAINTY* ADJA* ADJD* DIAG|ANATOM ADJA* ADJD* (?<!BREAK)')
    my %slc = ('...' => '...');
    my $entity = 'AAA';
    my $result = '';
    for (map { $_->{name} } (@$content_array))
    {
        $slc{$_}//= $entity++;;
        $result.=$slc{$_};
    }
    $query = join '', map {
            my ($pre, $mid, $post) = $_ =~/^([^A-Z]*)([A-Z\|]+)([^A-Z]*)/o;
            $mid = join '|', map {$slc{$_} || 'ZZZ'} split /\|/o, $mid;
            "$pre($mid)$post"
    } split / /,$query;

    while($result=~/$query/gs)  # let perl do the heavy lifting to make this grammar work
    {
        my ($start_position, $end_position) = ($-[0] / 3, ($+[0] - 1) / 3);
        my $content = join '', map {"<$_->{name}>$_->{content}</$_->{name}>"} @$content_array[$start_position .. $end_position];
        push @$res, {name => $name, content => $content};

    }
};

###########################################
# generic dbi part

helper fetchFromTable => sub { my ($self, $table, $sessionid, $where)=@_;
	my $sql = SQL::Abstract::More->new;
	my $order_by=[];


	my @a;
	if(1|| $sessionid)		# implement session-bound serverside security
	{	my %session;
        #	tie %session, 'Apache::Session::File', $sessionid , {Transaction => 0};
        # $table='persons_fulltext' if $table eq 'persons';
		my @cols=qw/*/;
		my($stmt, @bind) = $sql->select( -columns  => [-distinct => @cols], -from => $table, -where=> $where, -order_by=> $order_by);
		my $sth = $self->db->prepare($stmt);
		$sth->execute(@bind);
		if($table eq 'documents')
        {
            my @res;
            while(my $c=$sth->fetchrow_hashref())
            {   $c->{content} = $self->preprocess_text($c->{content});
                push @res, $c;
            }
            return \@res;
        } else
        {
            return $sth->fetchall_arrayref({});
        }
	}
	return [];
};

get '/DBB/extracted_entities/idletter/:pk' => [pk=>qr/[0-9]+/] => sub
{	my $self = shift;
    my $pk  = $self->param('pk');
    my $c = $self->fetchFromTable('documents', undef, {id=> $pk})->[0];
    my $extractors = $self->fetchFromTable('extractors', undef, {idproject=> $c->{idproject}});
    my $text = $self->preprocess_text($c->{content});
    my $res = [];
    foreach my $ex (@$extractors)
    {
        $self->extract_entities($pk, $text, $ex->{extractor}, $ex->{name}, $pk, $res);
    }

    $self-> render(json => $res);
};

# fetch all entities
get '/DBB/:table'=> sub
{	my $self = shift;
	my $table  = $self->param('table');
	my $sessionid  = $self->param('session');
	my $res=$self->fetchFromTable($table, $sessionid, {});
	$self-> render( json => $res);
};

# fetch entities by (foreign) key
get '/DBB/:table/:col/:pk' => [col=>qr/[a-z_0-9\s]+/, pk=>qr/[a-z0-9\s\-_\.]+/i] => sub
{	my $self = shift;
	my $table  = $self->param('table');
	my $pk  = $self->param('pk');
	my $col  = $self->param('col');
	my $sessionid  = $self->param('session');
	my $res=$self->fetchFromTable($table, $sessionid, {$col=> $pk});
	$self-> render( json => $res);
};

# update
put '/DBB/:table/:pk/:key'=> [key=>qr/\d+/] => sub
{	my $self	= shift;
	my $table	= $self->param('table');
	my $pk		= $self->param('pk');
	my $key		= $self->param('key');
	my $sql		= SQL::Abstract->new;

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
{	my $self	= shift;
	my $table	= $self->param('table');
	my $pk		= $self->param('pk');
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
{	my $self	= shift;
	my $table	= $self->param('table');
	my $pk		= $self->param('pk');
	my $key		= $self->param('key');
	my $sql = SQL::Abstract->new;

	my($stmt, @bind) = $sql->delete($table, {$pk=>$key});
	my $sth = $self->db->prepare($stmt);
	$sth->execute(@bind);
	app->log->debug("err: ".$DBI::errstr ) if $DBI::errstr;
	$self->render( json=>{err=> $DBI::errstr} );
};		


helper LDAPChallenge => sub { my ($self, $name, $password)=@_;
    return 1;
    my $ldap = Net::LDAP->new( 'ldap://ldap.ukl.uni-freiburg.de' );
	my $msg = $ldap->bind( 'uid='.$name.', ou=people, dc=ukl, dc=uni-freiburg, dc=de', password => $password);
	return $msg->code==0;
};

post '/AUTH' => sub {
	my $self=shift;
	my $user= $self->param('u');
	my $pass= $self->param('p');
	my $sessionid='';
	if($user)
	{	if($self->LDAPChallenge($user,$pass))
		{	my  %session;
			tie %session, 'Apache::Session::File', undef , {Transaction => 0};
			$sessionid = $session{_session_id};
			$session{username}=$user;
		}
	} $self->render(text => $sessionid );
};

helper getObjectFromTable => sub { my ($self, $table, $id, $dbh_dc)=@_;
	my $dbh  = $dbh_dc? $dbh_dc: $self->db;
	return undef if $id eq 'null' ||  $id eq 'NULL' ||  $id eq '';
	my $sth = $dbh->prepare( qq/select * from "/.$table.qq/" where id=?/);
	$sth->execute(($id));
	return $sth->fetchrow_hashref();
};


###################################################################
# main()

app->config(hypnotoad => {listen => ['http://*:3000'], workers => 5, heartbeat_timeout=>1200, inactivity_timeout=> 1200});
app->start;
