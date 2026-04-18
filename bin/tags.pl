#!/usr/bin/env perl

use strict;

my $query = shift @ARGV;

foreach my $file (@ARGV) {
  my $lines;
  if ($query eq "") {
    open $lines, $file;
  } else {
    # https://perldoc.perl.org/perlopentut#Expressing-the-command-as-a-list
    open $lines, '-|', 'readtags', '-t', $file, '-e', '-p', '-Q', "(#/^[^[:space:]]*$query\$/ \$name)", '-l';
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
