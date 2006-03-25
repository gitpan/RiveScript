#!/usr/bin/perl -w

use strict;
use warnings;

&scanPods ("./lib");

sub scanPods {
	my $dir = shift;

	my $docDir = $dir;
	$docDir =~ s~^\./lib~~i;
	$docDir =~ s~^\/~~i;
	mkdir ("./docs/$docDir") unless (-d "./docs/$docDir");

	opendir (DIR, $dir);
	foreach my $file (sort(grep(!/^\./, readdir(DIR)))) {
		if (-d "$dir/$file") {
			&scanPods ("$dir/$file");
		}
		if ($file =~ /\.(pm|pod)$/i) {
			my $htm = $file;
			$htm =~ s/\.$1$//i;
			print "Creating POD for $dir/$file\n";
			system ("pod2html $dir/$file > ./docs/$docDir/$htm\.html");
		}
	}
	closedir (DIR);
}