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

#step 8 - pridej 856 link na info o vzdalenem pristupu, pokud uz neni
if ( not( checkSubfield('85642','$$y* Návod pro Bookport')  ) ) {
   addField('85642','L','$$uhttps://dokumenty.osu.cz/knihovna/bookport.pdf$$y* Návod pro Bookport$$4N');
   }
changeFieldRegex('85640','L','\$\$y[^\$]+','','ALL'); #delete all subfields y
addSubfield ('85640','L','$$yPlný text PDF (Bookport)$$4N','ALL');




#end - print results
map { print "$_\n"; } @record;



