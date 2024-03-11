#!/usr/bin/env perl

use strict;

my $prefix = shift @ARGV;

foreach my $file (@ARGV) {
  my $lines;
  if ($prefix eq "") {
    open $lines, $file;
  } else {
    # https://perldoc.perl.org/perlopentut#Expressing-the-command-as-a-list
    open $lines, '-|', 'readtags', '-t', $file, '-e', '-p', '-', $prefix;
  }
  while (<$lines>) {
    unless (/^\!/) {
      s/^[^\t]*/sprintf("%-24s", $&)/e;
      s/$/\t$file/;
      print;
    }
  }
  close $lines;
}
