#!/usr/bin/env perl

use strict;

foreach my $file (@ARGV) {
  open my $lines, $file;
  while (<$lines>) {
    unless (/^\!/) {
      s/^[^\t]*/sprintf("%-24s", $&)/e;
      s/$/\t$file/;
      print;
    }
  }
  close $lines;
}
