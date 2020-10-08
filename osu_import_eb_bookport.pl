#!/exlibris/aleph/a23_1/product/bin/perl
#slouzi k uprave zaznamu pri importu
#pouzito pro import eknih Ebsco, zaznamu stazenych jako sada z OCLC
#
#NOTE - lnuli nutnosti zachovani puvodniho trideni hashrefu pouziva pridany modul Tie::StoredOrderHash  ktery neni v aleph distirbuci perlu
#
#Matyas B. 20150918
use strict; 
use warnings;
use utf8;
binmode STDOUT, ":utf8";
#binmode STDIN, ":encoding(UTF-8)";
binmode STDIN, ":utf8";
binmode STDERR, ":utf8";
use open ":encoding(utf8)";
use POSIX qw/strftime/;
use Data::Dumper; 
use DBI;
use Scalar::Util qw(looks_like_number);
use LWP::Simple;
use Env;

use HTML::Entities;
use URI::Escape qw( uri_escape_utf8 );
$ENV{NLS_LANG} = 'AMERICAN_AMERICA.AL32UTF8';


my $logFile=$ENV{'alephe_scratch'}."osu_import_eb_bookport.log";
my $sid = 'dbi:Oracle:host=localhost;sid=aleph23';
my $bibBase='osu01';
my $autBase='osu10';
my $xServerUrl='http://katalog.osu.cz/';


sub raiseError {
   my $msg = $_[0]; my $errtype = $_[1];
   my $timestamp = strftime "%Y%m%d-%H:%M:%S", localtime;
   open ( LOGFILE, ">>$logFile" );
   print LOGFILE "\n$timestamp - ";
   if ( $errtype eq 'error' ) { print LOGFILE "\n$timestamp ERROR: $msg\n"; }
   else { print LOGFILE "\n$timestamp WARNING: $msg\n"; }
   print LOGFILE "$msg\n";
   close(LOGFILE);  
   }

sub urlencode {
  local ($_) = @_;
  s/([^A-Za-z\d\-])/'%'.unpack('H2',$1)/eg;
  return $_;
}

our @record;
$bibBase = lc $bibBase;
my $bibBaseUp = uc $bibBase;
my $dollar='$';
my $aes=$ENV{'alephe_scratch'};
my $ds = $aes; $ds =~ s/alephe/$bibBase/;
my $alephProc=$ENV{'aleph_proc'};

#SUBROUTINES/PROCEDURES for manipulating the record (seek, replace, delete, add]
sub addField { #adds a new field to the record. Adds it at the end of the rec, which might be later changed on import to Aleph
   my ($sfield, $sdir, $scontent) = @_;
   return 0 unless ( $sfield and $sdir and $scontent) ;
   $sfield=substr($sfield,0,5); $sfield .= ' ' until (length($sfield)>=5);
   unless ( length($sdir)==1 ) { $sdir='L'; }
   push (@record,"$sfield$sdir$scontent");
   return 1
   }

sub addSubfield { #adds a new subfield at the end of the field, last param occur can gave a value 'ALL' - add in all occurences of the field, instead of just a first one
   my ($sfield, $sdir, $snew, $soccur) = @_;
   return 0 unless ( $sfield and $sdir and $snew) ;
   $sfield=substr($sfield,0,5); $sfield .= ' ' until (length($sfield)>=5);
   $soccur='' unless ( length( $soccur || '' ) );
   for my $i (0 .. $#record) {
      if ( $record[$i] =~ m/^\Q$sfield\E/ ) {
         $record[$i] .= $snew;
         last unless ( uc $soccur eq 'ALL' ); 
         }
      }
   return 1
   }

sub changeField { #changes the field contents from 'sfrom' to 'sto'. last param occur can gave a value 'ALL' - add in all occurences of the field, instead of just a first one
   my ($sfield, $sdir, $sfrom, $sto, $soccur) = @_;
   return 0 unless ( $sfield and $sdir and $sfrom and $sto);
   $sfield=substr($sfield,0,5); $sfield .= ' ' until (length($sfield)>=5);
   $soccur='' unless ( length( $soccur || '' ) );
   for my $i (0 .. $#record) {
      last unless ($record[$i] );
      if ( $record[$i] =~ m/^\Q$sfield\E\s*\Q$sdir\E/ ) {
         $record[$i] =~ s/\Q$sfrom\E/$sto/; 
         last unless ( uc $soccur eq 'ALL' ); }
      }
   return 1
   }

#sub delSubfield for deleting subfields does not exist. But you may use changeFieldRegex for matching the whole subfield. 
#          Per exemplum: for deleting subfield c use:
#          changeFieldRegex('020  ','L','\$\$c[^\$]+','','ALL')

sub changeFieldRegex { #usage of Regular Expressions possible on matching the text to be replaced. Do not forhet to escape dollars as subfield signs
   my ($sfield, $sdir, $sfrom, $sto, $soccur) = @_;
   return 0 unless ( $sfield and $sdir and $sfrom and $sto);
   $sfield=substr($sfield,0,5); $sfield .= ' ' until (length($sfield)>=5);
   $soccur='' unless ( length( $soccur || '' ) );
   for my $i (0 .. $#record) {
      last unless ($record[$i] );
      if ( $record[$i] =~ m/^\Q$sfield\E\s*\Q$sdir\E/) {
         $record[$i] =~ s/$sfrom/$sto/;
         last unless ( uc $soccur eq 'ALL' ); }
      }
   return 1;
   }

sub delField { #deletes a field.  last param occur can gave a value 'ALL' - delete all these fiels, not just the first one
   my ($sfield, $soccur) = @_;
   $soccur='' unless ( length( $soccur || '' ) );
   return 0 unless ( length( $sfield || '' ) );
   for my $i (0 .. $#record) {
      last unless ( $record[$i] );
      if ( $record[$i] =~ m/^\Q$sfield\E/ ) { 
         splice ( @record, $i, 1 );
         last unless ( uc $soccur eq 'ALL' ); }
      }
   return 1;
   }

sub checkField { #seeks field with indicators 
   my $sfield = $_[0];
   foreach ( @record ) {
      if ( $_ =~ m/^\Q$sfield\E/ ) { return 1;}
      }
   return 0;
   }

sub checkSubfield { #seeks fields contents
   my ($sfield, $scontents) = @_;
   $scontents=''  unless ( length( $scontents || '' ) );
   foreach ( @record ) {
      if ( $_ =~ m/^\Q$sfield\E\s*L\s*.*\Q$scontents\E/ ) { return 1;}
      }
   return 0;
   }

sub getField { #get field subfields, 2nd param can be determined if just one field or more. For 'all' occurencies returns an array!
   my ($sfield, $soccur) = @_;
   $soccur='' unless ( length( $soccur || '' ) );
   return '' if ( $sfield eq '' );
   my @retval;
   foreach ( @record ) {
      my $sline=$_;
      if ( $sline =~ m/^\Q$sfield\E/ ) { 
         $sline =~ s/^\Q$sfield\E\s*L\s*(.*)$dollar/$1/;
         push(@retval, $sline);
         }
      }
   if ( length(@retval)==0 ) { return ''; }
   if ( uc $soccur eq 'ALL' ) { 
      return @retval;
       }
   if ( looks_like_number($soccur)) {
      if ( $soccur eq $soccur+0 and $soccur<length(@retval) ) { return $retval[$soccur]; }
      }
   elsif ( $soccur eq '' and length(@retval)>0 ) { #return first value as scalar
      return $retval[0]; 
      }
   else {
      return '';
      }
   }

sub getSubfield { #get frist occurece of subfiled in a defined field. 3rd param sets which occurance of field would be taken: 0,1,2,... all (for all sub returns an array!]
   my ($sfield, $ssubfield, $soccur) = @_;
   $soccur='' unless ( length( $soccur || '' ) );
   return '' if ( $sfield eq '' );
   return '' if ( $ssubfield eq '' );
   $ssubfield = substr($ssubfield,0,1);
   my @retval;
   foreach ( @record ) {
      my $sline=$_;
      if ( $sline =~ m/^\Q$sfield\E\s*L\s*.*\$\$\Q$ssubfield\E/ ) { 
         $sline =~ s/^.*(\$\$\Q$ssubfield\E[^\$\$]*).*$dollar/$1/ ;
         push (@retval,$sline);
         }
      }
   if ( length(@retval)==0 ) { return ''; }
   foreach ( @retval ) { $_ =~ s/^\$\$.// ;}
   if ( uc $soccur eq 'ALL' ) { return @retval; }
   if ( looks_like_number($soccur) and $soccur<=length(@retval) ) { return $retval[$soccur-1]; }
   return '';
   }
 


while (<>) { # read lines from BIB record, one by one, and create an array containf the record
   my $line=$_;


###   if(utf8::is_utf8($line)) { utf8::decode($line);}
###   utf8::decode($line) or die("Not valid UTF-8 - line: $line");

   $line =~ s/^\s+|\s+$dollar//g;
   if ( $line eq '' ) {last;}
   if ( not ($line =~ m/^$bibBase/i) ) { push (@record, $line); }
   }

#CHANGES
#step 1 - pridel pole 040, pokud neni. A pokud pole 040 je, zmen jazyk na cestinu a pridej siglu
if ( checkField('040  ') ) {
   if ( not( checkSubfield('040  ','$$dOSD001')  ) ) { addSubfield('040  ','L','$$dOSD001',''); }
   if ( checkSubfield('040  ','$$b') ) { 
      changeFieldRegex ('040  ','L','\$\$b...','$$bcze',''); }
   else { addSubfield ('040  ','L','$$bcze'); }
   }
else {
   addField('040  ','L','$$aOSD001$$bcze$$erda'); }


#step 2 - pole FMT at je EB
delField('FMT  ','all');
addField('FMT  ','L','EB'); 

#step 3 - pridej pole BAS s nastavenou hodnotou   
my $BASfieldValue='$$aebooks - bookport';
addField('BAS  ','L',$BASfieldValue);

#step 3A - oprav pole 007   
delField('007  ','all');
addField('007  ','L','cr-|n|||||||||');

#step 3B - dej online verzi do pole 008
my $field008=getField('008','');
my $newfield008=substr($field008,0,23).'o'.substr($field008,24);
changeField('008  ','L',$field008,$newfield008);

#step 3B - pokud je 072 fikce, dej beletrii do pole 008, jinak tam dej nulu. Item se doplni deti/mladez dle 072
my $field072=getField('072','');
if ( $field072 =~ /\$\$aFIC/ ) {
   $newfield008=substr($newfield008,0,33).'1'.substr($newfield008,34);
   }
elsif ( $field072 =~ /\$\$aJUV/ ) {
   $newfield008=substr($newfield008,0,22).'j'.substr($newfield008,23);
   $newfield008=substr($newfield008,0,33).'1'.substr($newfield008,34);
   }
else {
   $newfield008=substr($newfield008,0,33).'0'.substr($newfield008,34);
   }
changeField('008  ','L',$field008,$newfield008);

#step 4 - z isbn 020 odstran cenu v podpoli c a print isbn zmen na neplatne (toto ne,m le lenkz je print v podpoli a OK)
##  nakonec vubec toto nedelej
#changeFieldRegex('020  ','L','\$\$c[^\$]+','','ALL');
#my @isbnsIN=getField('020','all');
#my @isbnsOUT;
#my $printISBN='';  ##POUZIVA TO DALSI STEP PRO Z39.50!!!!
#foreach ( @isbnsIN ) {
#   my $heading = '020  L'.$_;
#   if ( $heading =~ /\$\$q\(print\)/ ) {
#      $printISBN = $heading;
#      $printISBN =~ s/^.*\$\$a//;
#      $printISBN =~ s/\$\$.*$//;
#      }
#   $heading =~ s/\$\$c[^\$]+//;
#   push(@isbnsOUT,$heading);
#   }
#delField('020  ','ALL');
#foreach(@isbnsOUT) { push (@record,$_); }

#step 5 - pridej diakritiku do po pole 245
my @ititle = (0..1);
my @jtitle = (0..5);
foreach (@ititle) {
  my $itit=$_;
  foreach (@jtitle) {
    my $jtit=$_;
    changeFieldRegex('245'.$itit.$jtit,'L','\$\$b',' :$$b','');
    changeFieldRegex('245'.$itit.$jtit,'L',': :\$\$b',':$$b','');
    changeFieldRegex('245'.$itit.$jtit,'L','\$\$c',' /$$c','');
    changeFieldRegex('245'.$itit.$jtit,'L','/ /\$\$c','/$$c','');
    changeFieldRegex('245'.$itit.$jtit,'L','\$\$n','.$$n','');
    changeFieldRegex('245'.$itit.$jtit,'L','\.\.\$\$n','.$$n','');
    changeFieldRegex('245'.$itit.$jtit,'L','\$\$p',',$$p','');
    changeFieldRegex('245'.$itit.$jtit,'L',',,\$\$p',',$$p','');
    }
  }
#step 6 - pole 264 1 pridej podpole a pokud neni a dopln diakritiku
if ( checkField('264 1') ) {
   if ( not( checkSubfield('264 1','$$a')  ) ) { changeFieldRegex('264 1','L','264 1L','264 1L$$a[Místo vydání není známé] :'); }
   changeFieldRegex('264 1','L','\$\$b',' :$$b','');
   changeFieldRegex('264 1','L',': :\$\$b',':$$b','');
   changeFieldRegex('264 1','L','\$\$c',',$$c','');
   changeFieldRegex('264 1','L',',,\$\$c',',$$c','');
   }

#step 7- odstran html entity z pole 520
my $anotation=getField('520','');
changeField ('520  ','L',$anotation,decode_entities($anotation),''); 
my @ianot = (0..9);
foreach (@ianot) {
   changeField ('520'.$_.' ','L',$anotation,decode_entities($anotation),''); 
   }

#step 8 - pridej 856 link na info o vzdalenem pristupu, pokud uz neni
if ( not( checkSubfield('85642','$$y* Návod pro Bookport')  ) ) {
   addField('85642','L','$$uhttps://dokumenty.osu.cz/knihovna/bookport.pdf$$y* Návod pro Bookport$$4N');
   }
changeFieldRegex('85640','L','\$\$y[^\$]+','','ALL'); #delete all subfields y
addSubfield ('85640','L','$$yPlný text PDF (Bookport)$$4N','ALL');

#step 9A - pokusi se ziskat vecny popis a pole 1xx,7xx ze Souborneho katalogu pomoci dohledani a stazeni pres Z39.50
my $printISBN='';
my @isbnsIN=getField('020','all');
foreach ( @isbnsIN ) {
   my $isbnIN=$_;
   if ( $isbnIN =~ /\$\$q\(print\)/ ) {
      $printISBN = $isbnIN;
      $printISBN =~ s/^.*\$\$a//;
      $printISBN =~ s/\$\$.*$//;
      last;
      }
   }
if ( $printISBN ne '' ) {
   my $z39target='aleph.nkp.cz:9991';
   my $z39base='SKC-UTF'; 
   unlink "$ds/bookport_z39.tmp" or print "    debug file tmp not deleted\n";
   unlink "$ds/bookport_z39.seq" or print "    debug file seq not deleted\n";
   #get rec from z39.50
   system ('printf "base '.$z39base.'\nfind @attr 1=7 '.$printISBN.'\nshow" | $aleph_exe/yaz_client "'.$z39target.'" -m '.$ds.'/bookport_z39.tmp >/dev/null 2>&1');
   if ( -e "$ds/bookport_z39.tmp" ) { if ( -s "$ds/bookport_z39.tmp" ) {
      #convert isomarc to aleph sequential
      system ( "csh -f $alephProc/p_file_02 '".uc($bibBase).",bookport_z39.tmp,bookport_z39.seq,01,' >/dev/null 2>&1" ); 
      if ( -e "$ds/bookport_z39.seq" ) { if ( -s "$ds/bookport_z39.seq" ) {
         #select files that will be imported from downloaded z39 record
         system ( "sed 's/^000000001 //' $ds/bookport_z39.seq | sed 's/ L /L/' | grep -e '^041' -e '^043' -e '^045' -e '^072 7' -e '^080' -e '^1' -e '240' -e '^60' -e '^61' -e '^648 7' -e '^65007' -e '651 7' -e '655 7' -e '^7' | grep -v '^910' >$ds/bookport_z39.seq2imp");
         if ( -e "$ds/bookport_z39.seq2imp" ) { if ( -s "$ds/bookport_z39.seq2imp" ) {
            #followinf fields should be replaced insted of added, delete them before addition
            delField('1','ALL');
            delField('7','ALL');
            delField('041','ALL');
            delField('240','ALL');
            system ("cat $ds/bookport_z39.seq2imp");
            } } 
         } } 
      } } 
   }



#step 9B - navazeni na tezou sh
#pouziva x-server, find na bazi osu10, na rejstirk gen. Pokud se najde, udela se pole s 2.ind.7 a prida se tezou, aby se navazalo.
my @shIN=getField('648','all');
push ( @shIN, getField('650','all') );
push ( @shIN, getField('655','all') );
my @shOUT;
foreach ( @shIN ) {
   my $heading2=$_;
   unless ( $heading2 =~ m/\$\$2tezou/ ) {
      my @hfield2 = $heading2 =~ m/^6\d\d../g;
      my @h2 = $heading2 =~ m/\$\$[^\$]+/g;
      foreach ( @h2 ) {
         my $h2c = substr($_,2);
         $h2c =~ s/\.$// ;
         $h2c = 'a'.lcfirst(substr($h2c,1));
         my $h2api = lcfirst(substr($h2c,1));
         my $apiResponse = get ( $xServerUrl.'X?op=find&code=gen&request='.uri_escape_utf8('"'.$h2api.' tezou"').'&base='.$autBase );
         if ( defined $apiResponse) {
            $apiResponse =~ /<\s*no_records\s*>\s*\d+\s*<\s*\/\s*no_records\s*>/ ;
            if ( $apiResponse =~ /<\s*no_records\s*>\s*\d+\s*<\s*\/\s*no_records\s*>/ ) {
               my $noRecs=$&;
               $noRecs =~ s/\s*<[^>]*>\s*//g;
               if ( looks_like_number($noRecs) ) {
                  if ( looks_like_number($noRecs) > 0 ) {
                      push ( @shOUT, substr($hfield2[0],0,4).'7L$$a'.substr($h2c,1).'$$2tezou' ); 
                      }
                  }
               }
            }
         }
      }
   }
sub uniqArray { my %seen;  grep !$seen{$_}++, @_; } #got from http://perldoc.perl.org/perlfaq4.html#How-can-I-remove-duplicate-elements-from-a-list-or-array%3f
@shOUT = uniqArray(@shOUT);
foreach(@shOUT) {
   push (@record,$_); }
   
#step 9A - pridej pole 655 (povinne rda) - elektronicke knihy
addField ('655 7','L','$$aelektronické knihy$$2tezou');


#step10 - add IST field with date - used for news in the catalogue (both news by subject and carousel0
my $today = strftime "%Y%m%d", localtime;
addField ('IST  ','L','$$a'.$today );



#end - print results
map { print "$_\n"; } @record;



