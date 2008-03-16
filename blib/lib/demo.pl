#!/usr/bin/perl -w

use strict;
use warnings;
use lib "./lib";
use RiveScript;

my $rs = new RiveScript();

# Read the test directory.
$rs->loadDirectory ("./replies");
$rs->sortReplies();

while (1) {
	print "You> ";
	chomp (my $msg = <STDIN>);

	my $reply = $rs->reply ('localuser',$msg);

	print "Bot> $reply\n";
}
