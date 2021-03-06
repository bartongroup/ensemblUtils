#!/usr/bin/perl
package main;

=head1 NAME

ensembl_gene_bed_file.pl - for a given gene return a BED file with exon coordinates

=cut

use strict;
use warnings;

use Carp;
use Getopt::Long qw(:config auto_version);
use Pod::Usage;
use FindBin qw($Bin);
use lib "$Bin/lib";
use ensembl;
use Bio::EnsEMBL::ApiVersion;

my $geneID;
my $species = 'human';
my $out = 'out.bed';
my $VERBOSE = 0;
my $DEBUG = 0;
my $help;
my $man;
our $VERSION = '0.6';

## this script is a modulino, so check who's calling and respond appropriately
run() unless caller();

## run as script
sub run {
   
   $VERBOSE = 1; # turn on verbosity by default in script mode

   GetOptions (
      'gene-id=s' => \$geneID,
      'species=s' => \$species,
      'out=s'     => \$out,
      'verbose!'  => \$VERBOSE,
      'debug!'    => \$DEBUG,
      'man'       => \$man,
      'help|?'    => \$help,
   ) or pod2usage();

   pod2usage(-verbose => 2) if ($man);
   pod2usage(-verbose => 1) if ($help);
   pod2usage(-msg => 'Please supply a gene ID.') unless ($geneID);

   # load ensembl object
   my $ens = ensembl->new(species => $species, VERBOSE => $VERBOSE);
   print "Species: ", $ens->species, "\n" if $VERBOSE;
   
   # connect to ensembl and do some checks
   my $reg = $ens->connect();
   printf "NOTE: using Ensembl API version %s\n", software_version() if $VERBOSE;
   warn "Warning - API version check has failed. You probably need to update your local install.\n" unless ($reg->version_check($reg->get_DBAdaptor($species, 'core')));

   my $exons = exonCoordinates($reg, $geneID, $species);
   printf "Found %d exons\n", scalar keys %$exons if $VERBOSE;
   writeBedFile($exons, $out);
   print  "Written exon coordinates for gene '$geneID' to '$out'\n";
   
   exit();
}

# write a BED format file with the exon coordinates
sub writeBedFile {
   my $coords = shift;
   my $out = shift;
   
   open(my $BED, ">", $out) or die "ERROR - unable to open '$out' for write: ${!}\nDied";
   print $BED "track name=userDefinedExons\n";
   foreach my $ent (sort {$coords->{$a}{start} <=> $coords->{$b}{start}} keys %$coords) {
      printf $BED "%s\t%s\t%s\t$ent\t0\t%s\n", $coords->{$ent}{chr} , $coords->{$ent}{start}, $coords->{$ent}{end}, $coords->{$ent}{strand};
   }
   close($BED);
}

# connect to ensembl and extract exon coordinate data for the required gene
sub exonCoordinates {
   my $registry = shift;
   my $gid = shift;
   my $species = shift;
      
   my $gene_adaptor = $registry->get_adaptor($species, 'core', 'gene');
   die "ERROR - unable to connect to Ensembl for genes\n" unless ($gene_adaptor);
   my $trans_adaptor = $registry->get_adaptor($species, 'core', 'transcript');
   die "ERROR - unable to connect to Ensembl for genes\n" unless ($trans_adaptor);
   my $exon_adaptor = $registry->get_adaptor($species, 'core', 'exon');
   die "ERROR - unable to connect to Ensembl for genes\n" unless ($exon_adaptor);
   
   ## select gene
   my $gene;
   if ($gid =~ /^ENS.*G/) {
      # retrieve via stableid
      $gene = $gene_adaptor->fetch_by_stable_id($gid);
   } else {
      #my $g = $gene_adaptor->fetch_all_by_external_name($gid, 'HGNC');
      my $g = $gene_adaptor->fetch_all_by_display_label($gid);
      $g = ensembl->filterLRG($g); # filter out unwanted LRG 'genes'
      
      if (scalar @$g > 1) {
         my $count = scalar @$g;
         my $str = "";
         foreach $gene (@$g) {
            $str .= sprintf("   %s\t%s\t%s\n",$gene->stable_id(), $gene->external_name(), $gene->description());
         }
         die "ERROR - found $count genes with the name '$gid'. Try using an ensembl stable ID instead:\n$str\n";
      }
      die "ERROR - no genes found with the name '$gid'. Try again.\n" unless (scalar @$g);
      $gene = shift @$g;
   }
   print "Found gene '$gid'\n" if $VERBOSE;
   
   ## get all transcripts
   my $transcripts = $gene->get_all_Transcripts();
   printf "Found %d transcripts\n", scalar @$transcripts;
   
   my %data;
   ## for all transcripts get all exon ids
   foreach my $t (@$transcripts) {
      #printf "Transcript: %s\n", $t->stable_id();
      my $exons = $exon_adaptor->fetch_all_by_Transcript($t);
      foreach my $e (@$exons) {
         my $eid = $e->stable_id();
         #printf "Exon: %s\n", $eid;
         $data{$eid}{chr} = $e->seq_region_name();
         $data{$eid}{start} = $e->start();
         $data{$eid}{end} = $e->end();
         if ( $e->strand() == 1) {
            $data{$eid}{strand} = '+';
         } else {
            $data{$eid}{strand} = '-';
         }
      }
   }
   return(\%data);
}

=head1 SYNOPSIS

ensembl_gene_bed_file.pl --gene-id <string> [--species <string>] [--out <file>] [--verbose|--no-verbose] [--version] [--debug|--no-debug] [--man] [--help]

=head1 DESCRIPTION

Simple script to retrieve all exons for a given gene from ensembl and return exon coordinates in BED format.

Note: this is early code and not extensively tested YMMV.

=head1 OPTIONS

=over 5

=item B<--gene-id>

Gene ID (either HGNC or Ensembl).

=item B<--species>

Species. [default: human]

=item B<--out>

Output filename. [default: out.bed]

=item B<--version>

Report version information and exit

=item B<--verbose|--no-verbose>

Toggle verbosity. [default:none]

=item B<--debug|--no-debug>

Toggle debugging output. [default:none]

=item B<--help>

Brief help.

=item B<--man>

Full manpage of program.

=back

=head1 AUTHOR

Chris Cole <c.cole@dundee.ac.uk>

=head1 COPYRIGHT

Copyright 2014, Chris Cole. All rights reserved.

This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

=cut