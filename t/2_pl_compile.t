# this is a catch all to ensure all scripts compile
# added as lots of 'use' functionality is dynamic in pipeline
# and need to be sure that all modules compile.
# simple 'perl -c' is unlikely to work on head scripts any more.

use strict;
use Data::Dumper;
use Test::More;
use List::Util qw(first);
use Try::Tiny qw(try catch);
use autodie qw(:all);
use File::Find;

use FindBin qw($Bin);
my $script_path = "$Bin/../bin";

use constant COMPILE_SKIP => qw();

my $perl = $^X;

my @scripts;
find({ wanted => \&build_path_set, no_chdir => 1 }, $script_path);

# compiles now check can get a version

for(@scripts) {
  my $script = $_;
  if( first {$script =~ m/$_$/} COMPILE_SKIP ) {
    note("SKIPPING: Script with known issues: $script");
    next;
  }
  my $message = "Compilation check: $script";
  my $command = "$perl -c $script";
  my ($pass, $output) = exec_return($command);
  ok($pass, $message);

  $message = "Script version check (-v): $script";
  $command = "$perl $script -v";
  ($pass, $output) = exec_return($command);
  ok($pass, $message);
  if(pass) {
    chomp $output;
    if($output =~ m/^[[:digit:]]+\.[[:digit:]]+(\.[[:digit:]]+)?$/) {
      pass("Valid version string: $output ($script)");
    }
    else {
      fail("Invalid version string: $output ($script)");
    }
  }

  $message = "Script version check (-version): $script";
  $command = "$perl $script -version";
  ($pass, $output) = exec_return($command);
  ok($pass, $message);
}

sub exec_return {
  my $command = shift;
  my $output = q{};
  my $pass = 0;
  my ($pid, $process);
  try {
    $pid = open $process, $command.' 2>&1 |';
    while(<$process>){ $output .= $_; };
    close $process;
    $pass = 1;
  }
  catch {
    undef $output;
  };
  return ($pass, $output);
}


done_testing();

sub build_path_set {
  push @scripts, $_ if($_ =~ m/\.pl$/);
}
