package Jbrowse;

=pod

=head1 NAME

Shared constants and functions for main scripts

=head1 Functions

=over

=cut

use strict;
use autodie qw(:all);
use JSON;
use File::Copy qw(copy);
use File::Path qw(make_path remove_tree);
use FindBin qw($Bin);

our $VERSION = '1.0.0';
our @EXPORT = qw($VERSION);

use constant JQUERY => 'https://code.jquery.com/jquery-3.1.0.min.js';

use constant DEFAULT_BIOT => 'protein_coding';
use constant DEFAULT_TRAN => 'transcript';

sub fix_utr_gtf {
  my $options = shift;
  unless(Sanger::CGP::Jbrowse::need_utr_fix($options->{in})) {
    warn "File has no UTR entries, copying input\n";
    copy($options->{in}, $options->{out});
    return 1;
  }
  my $transcripts = gtf_transcripts($options->{in});

  open my $O_GTF, '>', $options->{out};

  open my $GTF, '<', $options->{in};
  while(<$GTF>) {
    if($_ =~ m/^#/) {
      print $O_GTF $_;
      next;
    }
    my @e = split /\t/, $_;
    next if($e[2] eq 'transcript');
    next if($e[2] eq 'gene');
    if($e[2] ne 'UTR') {
      print $O_GTF $_;
      next;
    }
    my ($trans_id) = $e[8] =~ m/transcript_id "([^"]+)/;
    fix_utr_line(\@e, $transcripts->{$trans_id});
    print $O_GTF join "\t", @e;
  }
  close $GTF;
  close $O_GTF;
}

sub fix_utr_line {
  my ($e, $trans) = @_;
  my $strand = $e->[6];
  my $e_start = $e->[3];
  my $e_stop = $e->[4];
  my $t_start = $trans->{start};
  my $t_stop = $trans->{stop};

  my $e_mid = int( ($e_stop - $e_start)/2 + $e_start);
  my $low_dist = $e_mid - $t_start;
  my $high_dist = $t_stop - $e_mid;

  if($low_dist < $high_dist) {
    if($strand eq '+') {
      $e->[2] = 'five_prime_UTR';
    }
    elsif($strand eq '-') {
      $e->[2] = 'three_prime_UTR';
    }
    else {
      die "Invalid strand: ".(join "\t", @{$e});
    }
  }
  elsif($high_dist < $low_dist) {
    if($strand eq '-') {
      $e->[2] = 'five_prime_UTR';
    }
    elsif($strand eq '+') {
      $e->[2] = 'three_prime_UTR';
    }
    else {
      die "Invalid strand: ".(join "\t", @{$e});
    }
  }
  else {
    die "Unexpected UTR:\n\t".(join "\t", @{$e});
  }

}

sub gtf_transcripts {
  my $in = shift;
  my %transcripts;
  open my $GTF, '<', $in;
  while(<$GTF>) {
    next if($_ =~ m/^#/);
    my ($feat_type, $start, $end, $info) = (split /\t/, $_)[2,3,4,8];

    next unless($feat_type eq 'transcript');

    my ($trans_id) = $info =~ m/transcript_id "([^"]+)/;
    $transcripts{$trans_id} = { start => $start,
                                stop => $end};
  }
  close $GTF;
  return \%transcripts;
}

sub need_utr_fix {
  my $gtf = shift;
  my $need_fix = 0;
  open my $GTF, '<', $gtf;
  while(<$GTF>) {
    next if($_ =~ m/^#/);
    my ($feat_type) = (split /\t/, $_)[2];
    if($feat_type eq 'UTR') {
      $need_fix++;
      last;
    }
  }
  close $GTF;
  return $need_fix;
}

=item subset_gff

Utility method used by both simple script and combined build script.

=cut

sub subset_gff {
  my ($options, $jb_gff) = @_;
  my $biotype = exists $options->{'biotype'} ? $options->{'biotype'} : DEFAULT_BIOT;
  my $type = exists $options->{'type'} ? $options->{'type'} : DEFAULT_TRAN;

  my $input = $options->{'gff3_in'};
  open my $GFF, '<', $input or die "$!: $input\n";
  open my $OUT, '>', $jb_gff or die "$!: $jb_gff\n";
  while (my $line = <$GFF>) {
    chomp $line;
    if($line =~ m/^#/ && $line ne '###') {
      print $OUT $line,"\n";
    }
    else{
      next unless($line =~ m/\tgene\t.+biotype=$biotype;/);
      print $OUT $line,"\n";
      my $do_line = 0;
      while($line = <$GFF>) {
        chomp $line;
        last if($line eq '###');
        if($line =~ m/Parent=gene:/) {
          if($line =~ m/\t$type\t/) {
            $do_line = 1;
          }
          else {
            $do_line = 0;
          }
        }
        print $OUT $line,"\n" if($do_line);
      }
      print $OUT "###\n";
    }
  }
  close $GFF;
  close $OUT;
  return 1;
}

sub confs_to_index {
  my ($options) = @_;
  my $deploy = $options->{'deploy'};
  my $idx_base = sprintf '%s/index', $deploy;
  remove_tree($idx_base) if(-e $idx_base);
  make_path($idx_base);

  my @sets;
  my @ul_li;
  my $title = $options->{'title'};

  my $base_query = sprintf '%s/*/*/JBrowse/jbrowse_conf.json', $deploy;
  my @confs = glob $base_query;
  for my $conf_path(sort @confs) {
    my ($species, $build) = $conf_path =~ m|^$deploy/([^/]+)/([^/]+)|;

    warn "$species, $build, $conf_path\n";

    my $json_data = q{};
    {
      local $/;
      open my $JS_FH, '<', $conf_path;
      $json_data = <$JS_FH>;
      close $JS_FH;
    }

    my $js = JSON->new->relaxed(1);
    my $confs = $js->decode( $json_data );

    my $links = q{};

    my $raw_ds = $confs->{datasets};
    my @datasets_live;
    my @datasets_test;
    for(keys %{$raw_ds}) {
      my $name = $raw_ds->{$_}->{name};
      my ($id) = $name =~ m/^t?(\d+)/;
      $raw_ds->{$_}->{'dataset_id'} = $id;
      if($name =~ m/^t/) {
        push @datasets_test, $raw_ds->{$_};
      }
      else {
        push @datasets_live, $raw_ds->{$_};
      }
    }

    for my $dataset(sort {$a->{dataset_id} <=> $b->{dataset_id}} @datasets_live) {
      $links .= sprintf q{<a href="/%1$s/%2$s/JBrowse/?data=auto/%3$s">%4$s</a><br/>}.qq{\n},
                                  $species, $build, $dataset->{dataset_id}, $dataset->{name};
    }
    for my $dataset(sort {$a->{dataset_id} <=> $b->{dataset_id}} @datasets_test) {
      $links .= sprintf q{<a href="/%1$s/%2$s/JBrowse/?data=auto/t%3$s">%4$s</a><br/>}.qq{\n},
                                  $species, $build, $dataset->{dataset_id}, $dataset->{name};
    }

    push @sets, {species => $species, build => $build, links => $links};
    push @ul_li, sprintf '<li><a id="%1$s_%2$s" href="/index/%1$s_%2$s.html#%1$s_%2$s">%1$s %2$s</a></li>', $species, $build;
  }

  my $ul_list = join "\n", @ul_li;

  my $html_format = base_html();
  for my $s(@sets) {
    my $sb_out = sprintf '%s/%s_%s.html', $idx_base, $s->{species}, $s->{build};
    open my $H_OUT, '>', $sb_out;
    printf $H_OUT $html_format, $title, $title, $ul_list, $s->{links};
    close $H_OUT;
  }

  my $final_index = sprintf '%s/index.html', $deploy;
  open my $IDX, '>', $final_index;
  printf $IDX $html_format, $title, $title, $ul_list, q{<p>Select tab to see available datasets</p>};
  close $IDX;

  copy("$Bin/../data/script.js", $idx_base.'/script.js');
  copy("$Bin/../data/style.css", $idx_base.'/style.css');
  my $cmd = sprintf 'wget -O %s/jquery.min.js %s', $idx_base, JQUERY;
  system($cmd);
}

sub base_html {
  return <<BASEHTML
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <title>%s</title>
    <script type="text/javascript" src="/index/jquery.min.js"></script>
    <script src="/index/script.js"></script>
    <link rel="stylesheet" href="/index/style.css">
  </head>
  <body>
  <div id="content">
    <h1>%s</h1>
    <div id="tab-container">
      <ul>
        %s
      </ul>
    </div>
    <div id="main-container">
      %s
    </div>
  </div>
  </body>
</html>
BASEHTML
}

1;

__END__

=back
