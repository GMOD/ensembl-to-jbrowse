#!/usr/bin/perl

use ExtUtils::MakeMaker;

WriteMakefile(
  NAME          => 'ensembl-to-jbrowse',
  VERSION_FROM  => 'lib/Jbrowse.pm',
  LICENSE       => 'mit', # http://search.cpan.org/~dagolden/CPAN-Meta-2.142690/lib/CPAN/Meta/Spec.pm#license
  EXE_FILES     => [qw( bin/buildIndex.pl
                        bin/ensemblToJbrowse.pl )],
  PREREQ_PM     => {
                     'Archive::Extract' => 0.80,
                     'Const::Fast' => 0.014,
                     'JSON' => 2.90,
                     'JSON::XS' => 3.01,
                   }
);
