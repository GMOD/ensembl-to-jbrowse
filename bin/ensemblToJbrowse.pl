#!/usr/bin/perl

=pod

=head1 NAME

ensemblToJbrowse.pl - Configure species under JBrowse using Ensembl

=head1 SYNOPSIS

ensemblToJbrowse.pl [options]

  Required parameters
    -delpoy    -d   Deploy to this path
    -jrelease  -j   Location of release []

  Parameters:
    -ensembl   -e   Link to FTP DNA area of Ensemble release [ftp://ftp.ensembl.org/pub/grch37/release-85/fasta/homo_sapiens/dna]
                     - can be defined multiple times (unless -remap is set)
    -biotype   -b   Biotype to select [protein_coding]
    -type      -t   Type of element to select, gene/transcript... (requires biotype to match) [transcript]
    -chr       -c   If true use chr prefixed data [0]
    -remap     -r   Remap chromosome names based on this file []

  Other:
    -help      -h   Brief help message.
    -man       -m   Full documentation.
    -version   -v   Print version.

=head1 DESCRIPTION

Given a 'deploy' location build the base reference area for a species using Ensembl as the datasource.
Will generate the relevant FASTA files, indexes and GFF annotation files.

Note expects 'samtools' on path.

=head1 OPTION DETAIL

=over

=item d|deploy

Base of deploy area.  Will construct folders for each species/build/release.

The most recently generated annotation release GFF will be linked into the build folder.

=item e|ensembl

The URL of the DNA ftp area. All other source data locations, species and
build information are constructed from this.  The species and ref-build are deduced from the
*.*.primary_assembly.fa.gz filename.  The Ensembl release from the 'release-XX' portion.

The resulting gff/fasta files will be named including all of this information.

=item b|biotype

What type of annotation track to construct, rare to modify [protein_coding]

=item t|type

The type of element to select [transcript]

=item j|jrelease

Provide a PATH or URL to the JBrowse zip (official release URL needs quoting).

=item c|chr

Select the GFF file with contig names prefixed with 'chr'

=item r|remap

Rename the contigs in the FASTA and GFF files using this mapping.

Format:

  ENSEMBL_NAME<tab>NEW_NAME

=back

=head1 Functions

=over

=cut

use strict;
use warnings FATAL => 'all';
use autodie qw(:all);
use FindBin qw($Bin);
use lib "$Bin/../lib";

use Getopt::Long;
use Pod::Usage qw(pod2usage);
use Const::Fast qw(const);
use File::Copy qw(move);
use File::Fetch;
use File::Path qw(make_path remove_tree);
use File::Temp qw(tempdir);

use Jbrowse;

use Data::Dumper;

use Archive::Extract;
$Archive::Extract::PREFER_BIN = 1;
$Archive::Extract::WARN = 1;

const my $DEFAULT_ENSE => 'ftp://ftp.ensembl.org/pub/grch37/release-85/fasta/homo_sapiens/dna';

my $options = opts();

my $tmp_dir = tempdir( CLEANUP => 1, DIR => $options->{'deploy'}, TEMPLATE => 'ensemblToJbrowse_XXXX');
$options->{'tmpdir'} = $tmp_dir;

for my $ense(@{$options->{'all_ensembl'}}) {
  $ense =~ s|/$||; # remove trailing '/' if present
  $options->{'ensembl'} = $ense;

  ensembl_ftp($options);
  prepare_ref($options);

  setup_jbrowse($options);
  remove_tree("$tmp_dir/*"); # empty the workspace between runs so we don't need a huge disk
}

sub setup_jbrowse {
  my $options = shift;

  my $deploy_area = sprintf '%s/%s/%s', $options->{'deploy'}, $options->{'species'}, $options->{'build'};

  my $jbrowse_final =  "$deploy_area/JBrowse";

  my $where;
  if(-e $options->{'jrelease'}) {
    $where = $options->{'jrelease'} # if a local file use in place
  }
  else {
    my $ff = File::Fetch->new(uri => $options->{'jrelease'});
    $where = $ff->fetch( to => $options->{'tmpdir'});
  }

  my $ae = Archive::Extract->new(archive => $where, type => 'zip');
  $ae->extract( to => $deploy_area ) or die $ae->error;

  my $jbrowse_base = $ae->extract_path;

  remove_tree($jbrowse_final) if(-e $jbrowse_final);
  move($jbrowse_base, $jbrowse_final);

  chdir $jbrowse_final;

  move('setup.sh', 'setup.sh.orig');
  system(q{grep -B 1000 -F 'To see the yeast example data, browse to http' setup.sh.orig > setup.sh});
  system(q{chmod u+x setup.sh});

  system(q{./setup.sh});


  my $jbin = "bin/";
  my $prs_cmd = $jbin;
  $prs_cmd .= q{prepare-refseqs.pl --seqType dna};
  $prs_cmd .= sprintf ' --indexed_fasta %s/genome.fa', $options->{'dest'};

  warn "Executing: $prs_cmd\n";
  system($prs_cmd) && die "Previous command failed: $!\n";

  my $fftj_cmd = $jbin;
  $fftj_cmd .= q{flatfile-to-json.pl};
  $fftj_cmd .= q{ --compress};
  $fftj_cmd .= q{ --trackType JBrowse/View/Track/CanvasFeatures};
  $fftj_cmd .= q{ --trackLabel protCodeTrans};
  $fftj_cmd .= q{ --key 'Transcripts'};
  $fftj_cmd .= q{ --config '{"displayMode" : "compact", "transcriptType": "transcript"}'};
  $fftj_cmd .= sprintf q{ --gff %s/jbrowse.gff3}, $options->{'dest'};

  warn "Executing: $fftj_cmd\n";
  system($fftj_cmd) && die "Previous command failed: $!\n";

  my $gn_cmd = $jbin;
  $gn_cmd .= q{generate-names.pl};
  $gn_cmd .= q{ --compress};
  $gn_cmd .= q{ --mem 768000000};

  warn "Executing: $gn_cmd\n";
  system($gn_cmd) && die "Previous command failed: $!\n";

}

sub prepare_ref {
  my $options = shift;

  if(defined $options->{'remap'}) {
    remap_contigs($options);
  }

  my $dest_dir = $options->{'dest'};

  ##
  # Ideally want to switch to 2bit support once available
  # wget https://github.com/ENCODE-DCC/kentUtils/raw/master/bin/linux.x86_64/faToTwoBit
  # chmod u+x faToTwoBit
  # ./faToTwoBit -noMask genome.fa genome.2bit
  ##

  my $faidx_cmd = sprintf 'samtools faidx %s/genome.fa', $dest_dir;
  warn "Indexing fasta: $faidx_cmd\n";
  system($faidx_cmd) && die "Failed to index reference sequence in $dest_dir: $!\n";

  if(exists $options->{'gff3_in'}) {
    warn "Subsetting GFF3\n";
    subset_gff($options);
  }
  else {
    warn "Converting GTF\n";
    convert_gtf($options);
  }
}

sub remap_contigs {
  my $options = shift;
  my %c_map;
  open my $REM, '<', $options->{'remap'};
  while(my $l = <$REM>) {
    chomp $l;
    my ($ours, $theirs) = split /\t/, $l;
    $c_map{$theirs} = $ours;
  }
  close $REM;

  my $dest_dir = $options->{'dest'};

  ## apply to ref seq first:
  my $fa_orig = sprintf '%s/genome.fa', $dest_dir;
  my $fa_new = sprintf '%s/genome.fa.tmp', $dest_dir;

  open my $FA_OUT, '>', $fa_new;
  open my $FA_IN, '<', $fa_orig;
  while (my $l = <$FA_IN>) {
    if($l =~ m/>([^[:space:]]+)/) {
      my $ctg = $1;
      chomp $ctg;
      printf $FA_OUT ">%s\n", $c_map{$ctg};
      next;
    }
    print $FA_OUT $l;
  }
  close $FA_IN;
  close $FA_OUT;

  unlink $fa_orig;
  move($fa_new, $fa_orig);

  ## gff3 file (bork if not gff3)
  die "ERROR: Remapping of contigs is only supported for GFF3 annotations\n" unless(exists $options->{'gff3_in'});

  my $gff3_orig = $options->{'gff3_in'};
  my $gff3_new = sprintf '%s/jbrowse.gff3.tmp', $dest_dir;

  open my $GFF3_OUT, '>', $gff3_new;
  open my $GFF3_IN, '<', $gff3_orig;
  while (my $l = <$GFF3_IN>) {
    if($l =~ m/^(##sequence-region[[:space:]]+)([^[:space:]]+)(.+)/) {
      printf $GFF3_OUT "%s%s%s\n", $1, $c_map{$2}, $3;
      next;
    }
    if($l =~ m/^#/) {
      print $GFF3_OUT $l;
      next;
    }
    $l =~ s/^([^\t]+)/$c_map{$1}/;
    print $GFF3_OUT $l;
  }
  close $GFF3_IN;
  close $GFF3_OUT;

  unlink($gff3_orig);
  move($gff3_new, $gff3_orig);

}

sub ensembl_ftp {
  my $options = shift;
  my $fasta_url = $options->{'ensembl'};

  my ($release) = $fasta_url =~ m|/release\-([[:digit:]]+)/|;

  my $ff = File::Fetch->new(uri => $fasta_url, tempdir_root => $options->{'tmpdir'});
  my $listing;
  my $where = $ff->fetch( to => \$listing );
  my $fa_type = 'primary_assembly';
  my ($fasta_file) = $listing =~ m/([^ ]+\.dna\.$fa_type\.fa\.gz)/xms;
  unless(defined $fasta_file) {
    $fa_type = 'toplevel';
    ($fasta_file) = $listing =~ m/([^ ]+\.dna\.$fa_type\.fa\.gz)/xms;
  }
  my ($species, $build) = $fasta_file =~ m/([^. ]+)\.([^[:space:]]+)\.dna\.$fa_type\.fa\.gz/xms;

  $build =~ s/\.${release}$//;

  die "ERROR: Could not derive species from folder content of URL: $fasta_url\n" if(!defined $species);
  die "ERROR: Could not derive build from folder content of URL: $fasta_url\n" if(!defined $build);
  die "ERROR: Could not derive release from URL: $fasta_url\n" if(!defined $release);

  # have info to build destination now
  my $dest_dir = sprintf '%s/%s/%s/%d', $options->{'tmpdir'}, $species, $build, $release;
  remove_tree($dest_dir) if(-e $dest_dir);

  warn "Writing to: $dest_dir\n";

  make_path($dest_dir);

  my $get_fasta = sprintf '%s/%s', $fasta_url, $fasta_file;
  warn "Fetching: $get_fasta\n";
  $ff = File::Fetch->new(uri => $get_fasta);
  $where = $ff->fetch( to => $dest_dir);

  warn "Unpacking: $fasta_file\n";
  system(sprintf 'gunzip -c %s/%s > %s/genome.fa', $dest_dir, $fasta_file, $dest_dir) && die "Failed to decompress $fa_type.fa.gz in $dest_dir: $!\n";

  my $release_base = $options->{'ensembl'};
  $release_base =~ s|/fasta.*||;

  $ff = File::Fetch->new(uri => $release_base, tempdir_root => $options->{'tmpdir'});
  $where = $ff->fetch( to => \$listing );
  my ($annot_type) = $listing =~ m/(gff3)$/xms;
  unless($annot_type) {
    ($annot_type) = $listing =~ m/(gtf)$/xms;
    die "Can't find a valid annot file, gff and gtf attempted\n" unless(defined $annot_type);
  }

  my $gxf_url = $options->{'ensembl'};
  $gxf_url =~ s|/dna$||;
  $gxf_url =~ s|/fasta/|/${annot_type}/|;

  my $get_gxf = sprintf '%s/%s.%s.%d.%s%s.gz', $gxf_url, $species, $build, $release, ($options->{'chr'} ? q{chr.} : q{}), $annot_type;
  warn "Fetching: $get_gxf\n";
  $ff = File::Fetch->new(uri => $get_gxf);
  $where = $ff->fetch( to => $dest_dir);
  warn "Unpacking: *.$annot_type.gz\n";
  system(sprintf 'gunzip -c %s/%s.%s.%d.%s%s.gz > %s/genome.%s', $dest_dir, $species, $build, $release, ($options->{'chr'} ? q{chr.} : q{}), $annot_type, $dest_dir, $annot_type) && die "Failed to decompress $annot_type.gz in $dest_dir: $!\n";

  unlink sprintf '%s/%s.%s.%d.%s%s.gz', $dest_dir, $species, $build, $release, ($options->{'chr'} ? q{chr.} : q{}), $annot_type;
  unlink sprintf '%s/%s', $dest_dir, $fasta_file;

  $options->{'species'} = $species;
  $options->{'build'} = $build;
  $options->{'release'} = $release;
  $options->{'dest'} = $dest_dir;

  $options->{$annot_type.'_in'} = sprintf '%s/genome.%s', $dest_dir, $annot_type;
  $options->{'fasta'} = sprintf '%s/genome.fa', $dest_dir;

  return 1;
}

=item convert_gtf

=cut

sub convert_gtf {
  my $options = shift;

  my $tmp_gtf = sprintf '%s/tmp.gtf', $options->{tmpdir};
  Jbrowse::fix_utr_gtf({in => $options->{gtf_in}, out => $tmp_gtf});
  unlink $options->{gtf_in};
  move($tmp_gtf, $options->{gtf_in});

  my $jb_gff = $options->{'dest'}.'/jbrowse.gff3';
#  my $cmd = sprintf "%s %s/gtf2gff.pl %s %s %s", $^X, $Bin, $options->{'gtf_in'}, $options->{'biotype'}, $jb_gff;
  my $cmd = sprintf "%s %s/gtf2gff3.pl --noclash --biotype protein_coding %s > %s", $^X, $Bin, $options->{'gtf_in'}, $jb_gff;
  warn "Executing: $cmd\n";
  system($cmd) && die "Failed to convert GTF to GFF3: $cmd";
  return 1;
}

=item subset_gff

See Jbrowse::subset_gff

=cut

sub subset_gff {
  my $options = shift;
  my $jb_gff = $options->{'dest'}.'/jbrowse.gff3';
  return Jbrowse::subset_gff($options, $jb_gff);
}

sub opts {
  my %opts = ('all_ensembl' => [$DEFAULT_ENSE],
              'biotype' => Jbrowse::DEFAULT_BIOT,
              'type' => Jbrowse::DEFAULT_TRAN,
              );
  GetOptions( 'h|help' => \$opts{'h'},
              'm|man' => \$opts{'m'},
              'v|version' => \$opts{'v'},
              'd|deploy=s' => \$opts{'deploy'},
              'e|ensembl:s@' => \$opts{'all_ensembl'},
              'b|biotype:s' => \$opts{'biotype'},
              't|type:s' => \$opts{'type'},
              'c|chr:i' => \$opts{'chr'},
              'j|jrelease=s' => \$opts{'jrelease'},
              'r|remap=s' => \$opts{'remap'},
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

  unless(defined $opts{'jrelease'}) {
    pod2usage(-message => qq{\nERROR: Option '-jrelease' must be defined.\n}, -verbose => 1, -exitval => 1);
  }

  if(defined $opts{'remap'} && scalar @{$opts{'all_ensembl'}} > 1) {
    pod2usage(-message => qq{\nERROR: Option '-remap' can only be defined with a single '-ensembl' option.\n}, -verbose => 1, -exitval => 1);
  }

  for(keys %opts) {
    delete $opts{$_} unless(defined $opts{$_});
  }

  return \%opts;
}

__END__

=back
