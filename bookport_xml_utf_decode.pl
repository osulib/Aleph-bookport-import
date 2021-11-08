#!/exlibris/product/bin/perl
use strict; use warnings;
use XML::Entities;
use utf8;
binmode(STDOUT, ":utf8");
binmode(STDIN, ":utf8");

#converts STDIN - xml hex utf entities to utf-9 encoding
#!!! MAKE THIS FILE EXECUTABLE first !
#!! SECOND:
 #This script requires XML::Entities module, not included in Aleph perl distribution. To add in type as aleph linux user:
 #                      /exlibris/product/bin/perl -MCPAN -eshell
 #                      install XML::Entities

foreach my $line ( <STDIN> ) {
    chomp( $line );
    $line = XML::Entities::numify('all', $line);
    $line = XML::Entities::decode('all', $line);
    print "$line\n";
}
