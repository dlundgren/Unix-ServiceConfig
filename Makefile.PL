require 5.006;
use strict;
use inc::Module::Install;
use Module::Install::Admin::Manifest;

name('Unix-ServiceConfig');
all_from('lib/Unix/ServiceConfig.pm');
author('David Lundgren <dlundgren@syberisle.net>');
abstract('System Services Configuration Interface');
license('mit');
requires(perl => 5.006);

use Getopt::Std;
my $opt_n;
unless(getopts("n")) { die "Usage: $0 [-n]\n"; }
my @programs_to_install = () if $opt_n;

install_script($_) foreach @programs_to_install;
clean_files($_)    foreach @programs_to_install;

# needed files
requires('Term::ReadLine');
requires('Term::ANSIColor');
requires('DBI');
requires('DBD::mysql');
requires('File::Basename');
requires('vpopmail');
# These are needed during `make all`:
build_requires('File::Spec');
# These are needed during `make test`:
build_requires('File::Temp');
build_requires('Test::File');
build_requires('Test::More');
build_requires('Test::Pod');
# I think there's a bug in Module::CoreList or something, because this
# comes up missing on some platforms:
build_requires('Test::Simple');
# For the defunct test_parsing rule, we need a version that sets
# FULLPERLRUNINST:
build_requires('ExtUtils::MM_Unix' => 1.41);


&WriteAll;

1;
