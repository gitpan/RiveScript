/*
	RiveScript // Objects Example

	This reply set declares two objects in-line.
*/

// Test loading Digest-MD5 outside of an object
! syslib Digest::MD5

> object encode
	my ($method,$data) = @_;

	my $md5 = new Digest::MD5;
	return $md5->md5_hex ($data);
< object

+ encode *
- Encoded: &encode.do(<star>)

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