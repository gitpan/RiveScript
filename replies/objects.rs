/*
	RiveScript // Objects Example

	This reply set declares two objects in-line.
*/

> object test
	my ($method,$data) = @_;

	print "\n"
		. "test object called! method = $method; data = $data\n\n";

	return "random number: " . int(rand(99999));
< object

> object uservars
	my ($method,$data) = @_;

	# Get uservars for 'localhost'
	print "\nGetting uservars for localhost\n";

	my $vars = $main::rs->getUservars ('localhost');

	foreach my $key (keys %{$vars}) {
		print "$key = $vars->{$key}\n";
	}

	print "\n";

	# Return blank.
	return '';
< object