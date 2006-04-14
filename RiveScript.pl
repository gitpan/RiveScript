#!/usr/bin/perl -w

use strict;
use warnings;
use RiveScript;

my $braindir = './replies';

my $debug = 0;
if (@ARGV) {
	$debug = 1 if $ARGV[0] eq '--debug';
}

print "RiveScript $RiveScript::VERSION Loaded\n";

print "Load brain from directory or <$braindir>: ";
my $dir = <STDIN>;
chomp $dir;
$braindir = $dir if length $dir;

# Create a new RS interpreter.
my $rs = new RiveScript (
	debug => $debug,
);

# Load in some RS files.
$rs->loadDirectory ($braindir);
$rs->sortReplies;

while(1) {
	print " In> ";
	my $in = <STDIN>;
	chomp $in;

	my @reply = $rs->reply ('localhost',$in);

	print "Out> $_\n" foreach(@reply);
}