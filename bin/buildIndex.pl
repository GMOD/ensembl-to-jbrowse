#!/usr/bin/perl

=pod

=head1 NAME

buildIndex.pl - Parses */*/JBrowse/jbrowse_conf.json and builds an index page with all links.

=head1 SYNOPSIS

buildIndex.pl [options]

  Required parameters
    -deploy    -d   Deploy to this path

  Other:
    -help      -h   Brief help message.
    -man       -m   Full documentation.
    -version   -v   Print version.

=head1 DESCRIPTION

Given a 'deploy' location build an index for all JBrowse configs held under the species/build
pathing:

  <SPECIES>/<BUILD>/JBrowse/jbrowse_conf.json

=cut

use strict;
use warnings FATAL => 'all';
use autodie qw(:all);
use FindBin qw($Bin);
use lib "$Bin/../lib";
use Getopt::Long;
use Pod::Usage qw(pod2usage);

use Jbrowse;

my $options = opts();

Jbrowse::confs_to_index($options);

sub opts {
  my %opts;
  GetOptions( 'h|help' => \$opts{'h'},
              'm|man' => \$opts{'m'},
              'v|version' => \$opts{'v'},
              'd|deploy=s' => \$opts{'deploy'},
  ) or pod2usage(2);

  pod2usage(-verbose => 1, -exitval => 0) if(defined $opts{'h'});
  pod2usage(-verbose => 2, -exitval => 0) if(defined $opts{'m'});

  if(defined $opts{'v'}) {
    print Jbrowse->VERSION,"\n";
    exit 0;
  }

  unless(defined $opts{'deploy'}) {
    pod2usage(-message => qq{\nERROR: Option '-deploy' must be defined.\n}, -verbose => 1, -exitval => 1);
  }

  unless(-X $opts{'deploy'}) {
    pod2usage(-message => qq{\nERROR: Option '-deploy' must exist and be writable.\n}, -verbose => 1, -exitval => 1);
  }

  return \%opts;
}
