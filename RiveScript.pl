#!/usr/bin/perl -w

use strict;
use warnings;
use RiveScript;
use Data::Dumper;

my $debug = 0;
if (@ARGV) {
	$debug = 1 if $ARGV[0] eq '--debug';
}

print "RiveScript $RiveScript::VERSION Loaded\n";

# Create a new RS interpreter.
my $rs = new RiveScript (debug => $debug);

# Load in some RS files.
$rs->loadDirectory ("./replies");
$rs->sortReplies;

# Set the bot to be 16 instead of 14 years old
$rs->setVariable (age => 16);

# Write all data to a new file.
$rs->write();

while(1) {
	print " In> ";
	my $in = <STDIN>;
	chomp $in;

	my @reply = $rs->reply ('localhost',$in,
		scalar => 1,
	);

	print "Out> $_\n" foreach(@reply);
}