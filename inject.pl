#!/usr/bin/perl -w
#
# inject.pl - perl script to install a CVS version of base-files into
#             an existing Fink tree
#
# Fink - a package manager that downloads source and installs it
# Copyright (c) 2001 Christoph Pfisterer
# Copyright (c) 2001-2003 The Fink Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
#

$| = 1;
use 5.006;  # perl 5.6.0 or newer required
use strict;

my ($basepath, $packageversion, $packagerevision);
my ($script, $cmd);

### check if we're unharmed

my ($file);
foreach $file (qw(dir-base init.sh.in setup.sh)) {
  if (not -e $file) {
    print "ERROR: Package incomplete, '$file' is missing.\n";
    exit 1;
  }
}

### locate Fink installation

my ($guessed, $param, $path);

$guessed = "";
$param = shift;
if (defined $param) {
  $basepath = $param;
} else {
  $basepath = undef;
  if (exists $ENV{PATH}) {
    foreach $path (split(/:/, $ENV{PATH})) {
      if (substr($path,-1) eq "/") {
	$path = substr($path,0,-1);
      }
      if (-f "$path/init.sh" and -f "$path/fink") {
	$path =~ /^(.+)\/[^\/]+$/;
	$basepath = $1;
	last;
      }
    }
  }
  if (not defined $basepath or $basepath eq "") {
    $basepath = "/sw";
  }
  $guessed = " (guessed)";
}
unless (-f "$basepath/bin/fink" and
	-f "$basepath/bin/init.sh" and
	-f "$basepath/etc/fink.conf" and
	-d "$basepath/fink/dists") {
  &print_breaking("The directory '$basepath'$guessed does not contain a ".
		  "Fink installation. Please provide the correct path ".
		  "as a parameter to this script.");
  exit 1;
}

### load some modules

unshift @INC, "$basepath/lib/perl5";

require Fink::Services;
import Fink::Services qw(&read_config &execute &file_MD5_checksum);
require Fink::Config;

### get version

chomp($packageversion = `cat VERSION`);
$packageversion .= ".cvs";
my @now = gmtime(time);
$packagerevision = sprintf("%04d%02d%02d.%02d%02d",
			   $now[5]+1900, $now[4]+1, $now[3],
			   $now[2], $now[1]);

### load configuration

my $config = &read_config("$basepath/etc/fink.conf");

### parse config file for root method

# TODO: use setting from config
# for now, we just use sudo...

if ($> != 0) {
  exit &execute("sudo ./inject.pl $basepath");
}
umask oct("022");

### check that local/bootstrap is in the Trees list

my $trees = $config->param("Trees");
if ($trees =~ /^\s*$/) {
  print "Adding a Trees line to fink.conf...\n";
  $config->set_param("Trees", "local/main stable/main stable/crypto local/bootstrap");
  $config->save();
} else {
  if (grep({$_ eq "local/bootstrap"} split(/\s+/, $trees)) < 1) {
    print "Adding local/bootstrap to the Trees line in fink.conf...\n";
    $config->set_param("Trees", "$trees local/bootstrap");
    $config->save();
  }
}

### create tarball for the package

print "Creating tarball...\n";

$script = "";
if (not -d "$basepath/src") {
  $script .= "mkdir -p $basepath/src\n";
}

$script .=
  "tar -cf $basepath/src/base-files-$packageversion.tar ".
  "COPYING init.csh.in init.sh.in dir-base ".
  "pager.in editor.in install.sh setup.sh\n";

foreach $cmd (split(/\n/,$script)) {
  next unless $cmd;   # skip empty lines

  if (&execute($cmd)) {
    print "ERROR: Can't create tarball.\n";
    exit 1;
  }
}

### create and copy description file

print "Copying package description...\n";

$script = "";
if (not -d "$basepath/fink/dists/local/bootstrap/finkinfo") {
  $script .= "mkdir -p $basepath/fink/dists/local/bootstrap/finkinfo\n";
}

my $md5 = &file_MD5_checksum("$basepath/src/base-files-$packageversion.tar");
$script .= "sed -e 's/\@VERSION\@/$packageversion/' -e 's/\@REVISION\@/$packagerevision/' -e 's/\@MD5\@/$md5/' <base-files.info.in >$basepath/fink/dists/local/bootstrap/finkinfo/base-files-$packageversion.info\n";

foreach $cmd (split(/\n/,$script)) {
  next unless $cmd;   # skip empty lines

  if (&execute($cmd)) {
    print "ERROR: Can't copy package description.\n";
    exit 1;
  }
}

### install the package

print "Installing package...\n";
print "\n";

if (&execute("$basepath/bin/fink install base-files")) {
  print "\n";
  &print_breaking("Installing the new base-files package failed. ".
		  "The description and the tarball were installed, though. ".
		  "You can retry at a later time by issuing the ".
		  "appropriate fink commands.");
} else {
  print "\n";
  &print_breaking("Your Fink installation in '$basepath' was updated with ".
		  "a new base-files package.");
}
print "\n";


### helper functions

sub print_breaking {
  my $s = shift;
  my ($pos, $t);
  my $linelength = 77;

  chomp($s);
  while (length($s) > $linelength) {
    $pos = rindex($s," ",$linelength);
    if ($pos < 0) {
      $t = substr($s,0,$linelength);
      $s = substr($s,$linelength);
    } else {
      $t = substr($s,0,$pos);
      $s = substr($s,$pos+1);
    }
    print "$t\n";
  }
  print "$s\n";
}

### eof
exit 0;
