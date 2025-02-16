#!/usr/bin/env perl

use strict;
use warnings;

use FindBin qw($Bin);
use lib $Bin;

use Xposed;

use Data::Dumper;
use File::Basename;
use File::Copy;
use File::Path qw(make_path);
use Getopt::Std;

our $VERSION = '1.0';

my %opts;
$| = 1;

# Main routine
sub main() {
    $Getopt::Std::STANDARD_HELP_VERSION = 1;
    getopts('iuv', \%opts) || usage(2);

    # Load the config file
    print_status("Loading config file $Bin/build.conf...", 0);
    $Xposed::cfg = Xposed::load_config("$Bin/build.conf") || exit 1;

    # Check some build requirements
    print_status('Checking requirements...', 0);
    Xposed::check_requirements() || exit 1;

    # Build XZ-Utils for the configured platforms
    my @platforms = $Xposed::cfg->Parameters('XZ-Utils');
    if (!@platforms) {
        print_error("No platforms found, please configure the [XZ-Utils] section!");
        exit 1;
    }
    foreach my $platform (@platforms) {
        build($platform, $Xposed::cfg->val('XZ-Utils', $platform)) || exit 1;
    }

    print_status('Done!', 0);
}

# Print usage and exit
sub usage($) {
    my $exit = shift;
    print STDERR <<USAGE;

This script helps to compile a static version of XZ-Utils.

Usage: $0 [-v] [-i] [-u]
  -i   Incremental build. Compile faster by skipping dependencies (like mm/mmm).
  -u   Update the xz-static files within this repository.
  -v   Verbose mode. Display the build log instead of redirecting it to a file.
USAGE
    exit $exit if $exit >= 0;
}

sub HELP_MESSAGE() {
    usage(-1);
}

sub VERSION_MESSAGE() {
    print "XZ-Utils for Xposed build script, version $VERSION\n";
}

# Compile XZ-Utils for one SDK/platform
sub build($$;$) {
    my $platform = shift;
    my $sdk = shift;

    print_status("Building for $platform on SDK $sdk...", 0);
    Xposed::check_target_sdk_platform($platform, $sdk) || return 0;

    my $rootdir = Xposed::get_rootdir($sdk) || return 0;
    my $outdir = Xposed::get_outdir($platform) || return 0;

    # Ensure that the arch-appropriate XZ-Utils config exists
    my $checkfile = "$rootdir/external/xz-utils/config.h." . ( $platform eq 'armv5' ? 'arm' : $platform );
    if (!-f $checkfile) {
        print_error("$checkfile not found, make sure XZ-Utils is set up correctly!");
        return 0;
    }

    my @params = Xposed::get_make_parameters($platform);
    push @params, 'XPOSED_BUILD_STATIC=true';
    my @targets = qw(xz);
    my @makefiles = qw(external/xz-utils/Android.mk);

    print_status("Compiling...", 1);
    Xposed::compile($platform, $sdk, \@params, \@targets, \@makefiles, $opts{'i'}, !$opts{'v'}, 'xz-utils') || return 0;

    # Copy the files to the output directories
    print_status("Copying files...", 1);
    my $file = "$rootdir/$outdir/system/bin/xz";
    system("strip $file") if $platform eq 'x86';
    my @copy_targets = ($Xposed::cfg->val('General', 'outdir') . "/xz-utils/xz-static-$platform");
    push @copy_targets, "$Bin/zipstatic/$platform/META-INF/com/google/android/xz-static" if $opts{'u'};
    foreach my $target (@copy_targets) {
        print "$file => $target\n";
        make_path(dirname($target));
        if (!copy($file, $target)) {
            print_error("Copy failed: $!");
            return 0;
        }
    }

    print "\n\n";

    return 1;
}

main();
