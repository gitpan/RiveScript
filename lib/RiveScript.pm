package RiveScript;

use Data::Dumper;
use strict;
use warnings;

our $VERSION = '1.14'; # Version of the Perl RiveScript interpreter.
our $SUPPORT = '2.0';  # Which RS standard we support.

################################################################################
## Constructor and Debug Methods                                              ##
################################################################################

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto || 'RiveScript';

	my $self = {
		debug     => 0,
		depth     => 50, # Recursion depth allowed.
		topics    => {}, # Loaded replies under topics
		sorted    => {}, # Sorted triggers
		sortsthat => {}, # Sorted %previous's.
		thats     => {}, # Reverse mapping for %previous, under topics
		arrays    => {}, # Arrays
		subs      => {}, # Substitutions
		person    => {}, # Person substitutions
		client    => {}, # User variables
		bot       => {}, # Bot variables
		objects   => {}, # Subroutines
		reserved  => [   # Reserved global variable names.
			qw(topics sorted sortsthat thats arrays subs person
			client bot objects reserved)
		],
		@_,
	};
	bless ($self,$class);

	$self->debug ("RiveScript $VERSION Initialized");

	return $self;
}

sub debug {
	my ($self,$msg) = @_;
	if ($self->{debug}) {
		print "RiveScript: $msg\n";
	}
}

sub issue {
	my ($self,$msg) = @_;
	if ($self->{debug}) {
		print "# RiveScript::Warning: $msg\n";
	}
	else {
		warn "RiveScript::Warning: $msg\n";
	}
}

################################################################################
## Parsing Methods                                                            ##
################################################################################

sub loadDirectory {
	my $self = shift;
	my $dir = shift || '.';
	my (@exts) = @_ || ('.rs');

	if (!-d $dir) {
		$self->issue ("loadDirectory failed: $dir is not a directory!");
		return 0;
	}

	$self->debug ("loadDirectory: Open $dir");

	opendir (DIR, $dir);
	foreach my $file (readdir(DIR)) {
		next if $file eq '.';
		next if $file eq '..';
		next if $file =~ /\~$/i; # Skip backup files
		foreach (@exts) {
			my $re = quotemeta($_);
			next unless $file =~ /$re$/;
		}

		$self->debug ("loadDirectory: Read $file");

		$self->loadFile ("$dir/$file");
	}
	closedir (DIR);

	return 1;
}

sub loadFile {
	my ($self,$file) = @_;

	if (not defined $file) {
		$self->issue ("loadFile requires a file path.");
		return 0;
	}

	if (!-f $file) {
		$self->issue ("loadFile failed: $file is not a file!");
		return 0;
	}

	open (READ, $file);
	my @code = <READ>;
	close (READ);
	chomp @code;

	# Parse the file.
	$self->debug ("loadFile: Parsing " . (scalar @code) . " lines from $file.");
	$self->parse ($file,join("\n",@code));

	return 1;
}

sub stream {
	my ($self,$code) = @_;

	if (not defined $code) {
		$self->issue ("stream requires RiveScript code.");
		return 0;
	}

	# Stream the code.
	$self->debug ("stream: Streaming code.");
	$self->parse ("stream()",$code);

	return 1;
}

sub parse {
	my ($self,$fname,$code) = @_;

	# Track temporary variables.
	my $topic   = 'random'; # Default topic=random
	my $lineno  = 0;        # Keep track of line numbers
	my $comment = 0;        # In a multi-line comment.
	my $inobj   = 0;        # Trying to parse an object.
	my $objname = '';       # Object name
	my $objbuf  = '';       # Object code buffer.
	my $ontrig  = '';       # Current trigger.
	my $repcnt  = 0;        # Reply counter.
	my $concnt  = 0;        # Condition counter.
	my $lastcmd = '';       # Last command code.
	my $isThat  = '';       # Is a %Previous trigger.

	# Split the RS code into lines.
	$code =~ s~([\x0d\x0a])+~\x0a~ig;
	my @lines = split(/\x0a/, $code);

	# Read each line.
	$self->debug ("Parsing file data from $fname");
	my $lp = 0; # line number index
	for ($lp = 0; $lp < scalar(@lines); $lp++) {
		$lineno++;
		my $line = $lines[$lp];

		# Chomp the line further.
		chomp $line;
		$line =~ s/^(\t|\x0a|\x0d|\s)+//ig;
		$line =~ s/(\t|\x0a|\x0d|\s)+$//ig;

		$self->debug ("Line: $line");

		# In an object?
		if ($inobj) {
			if ($line =~ /^<\s*object/i) {
				# End the object.
				if (length $objname) {
					$objbuf .= "\n}";
					eval ($objbuf);
					if ($@) {
						$self->issue ("Object creation failed: $@");
					}
					else {
						# Define the subroutine, too.
						$self->setSubroutine ($objname, \&{"RSOBJ_$objname"});
					}
				}
				$objname = '';
				$objbuf = '';
			}
			else {
				$objbuf .= "$line\n";
				next;
			}
		}

		# Look for comments.
		if ($line =~ /^(\/\/|#)/i) {
			next;
		}
		elsif ($line =~ /^\/\*/) {
			$comment = 1;
			next;
		}
		elsif ($line =~ /\*\//) {
			$comment = 0;
			next;
		}
		if ($comment) {
			next;
		}

		# Skip blank lines.
		next if length $line == 0;

		# Separate the command from the data.
		my ($cmd) = $line =~ /^(.)/i;
		$line =~ s/^([^\s]+)\s+//i;

		# Ignore inline comments if there's a space before and after
		# the // or # symbols.
		($line,undef) = split(/\s+(\#|\/\/)\s+/, $line, 2);

		$self->debug ("\tCmd: $cmd");

		# Do a lookahead for ^Continue and %Previous commands.
		for (my $i = ($lp + 1); $i < scalar(@lines); $i++) {
			my $lookahead = $lines[$i];
			my ($lookCmd) = $lookahead =~ /^(.)/i;
			$lookahead =~ s/^([^\s]+)\s+//i;

			if ($cmd eq '+') {
				# Look for %Previous.
				if ($lookCmd eq '%') {
					$self->debug ("\tIs a %previous ($lookahead)");
					$isThat = $lookahead;
					last;
				}
				else {
					$isThat = '';
				}
			}

			if ($cmd ne '^' && $lookCmd ne '%') {
				if ($lookCmd eq '^') {
					$self->debug ("\t^ [$lp;$i] $lookahead");
					$line .= $lookahead;
				}
				else {
					last;
				}
			}
		}

		if ($cmd eq '!') {
			# ! DEFINE
			my ($left,$value) = split(/\s*=\s*/, $line);
			my ($type,$var) = split(/\s+/, $left, 2);
			$ontrig = '';
			$self->debug ("\t! DEFINE");

			if ($type eq 'version') {
				$self->debug ("\tUsing RiveScript version $value");
				if ($value > $SUPPORT) {
					$self->issue ("Unsupported RiveScript Version. Skipping file $fname.");
					return;
				}
			}
			elsif ($type eq 'global') {
				if (not defined $var) {
					$self->issue ("Undefined global variable at $fname line $lineno.");
					next;
				}
				if (not defined $value) {
					$self->issue ("Undefined global value at $fname line $lineno.");
					next;
				}

				$self->debug ("\tSet global $var = $value");

				# Don't allow the overriding of a reserved global.
				my $ok = 1;
				foreach my $res (@{$self->{reserved}}) {
					if ($var eq $res) {
						$self->issue ("Can't override global variable $res at $fname line $lineno.");
						$ok = 0;
						last;
					}
				}

				if ($ok) {
					# Allow.
					if ($value eq '<undef>') {
						delete $self->{$var};
					}
					else {
						$self->{$var} = $value;
					}
				}
			}
			elsif ($type eq 'var') {
				$self->debug ("\tSet bot variable $var = $value");
				if (not defined $var) {
					$self->issue ("Undefined bot variable at $fname line $lineno.");
					next;
				}
				if (not defined $value) {
					$self->issue ("Undefined bot value at $fname line $lineno.");
					next;
				}

				if ($value eq '<undef>') {
					delete $self->{bot}->{$var};
				}
				else {
					$self->{bot}->{$var} = $value;
				}
			}
			elsif ($type eq 'array') {
				$self->debug ("\tSet array $var");
				if (not defined $var) {
					$self->issue ("Undefined array variable at $fname line $lineno.");
					next;
				}
				if (not defined $value) {
					$self->issue ("Undefined array value at $fname line $lineno.");
					next;
				}

				if ($value eq '<undef>') {
					delete $self->{arrays}->{$var};
					next;
				}

				# Split at pipes or spaces?
				my @fields = ();
				if ($value =~ /\|/) {
					@fields = split(/\|/, $value);
				}
				else {
					@fields = split(/\s+/, $value);
				}

				$self->{arrays}->{$var} = [ @fields ];
			}
			elsif ($type eq 'sub') {
				$self->debug ("\tSubstitution $var => $value");
				if (not defined $var) {
					$self->issue ("Undefined sub pattern at $fname line $lineno.");
					next;
				}
				if (not defined $value) {
					$self->issue ("Undefined sub replacement at $fname line $lineno.");
					next;
				}

				if ($value eq '<undef>') {
					delete $self->{subs}->{$var};
					next;
				}
				$self->{subs}->{$var} = $value;
			}
			elsif ($type eq 'person') {
				$self->debug ("\tPerson substitution $var => $value");
				if (not defined $var) {
					$self->issue ("Undefined person sub pattern at $fname line $lineno.");
					next;
				}
				if (not defined $value) {
					$self->issue ("Undefined person sub replacement at $fname line $lineno.");
					next;
				}
				if ($value eq '<undef>') {
					delete $self->{person}->{$var};
					next;
				}
				$self->{person}->{$var} = $value;
			}
			else {
				$self->issue ("Unknown definition type \"$type\" at $fname line $lineno.");
				next;
			}
		}
		elsif ($cmd eq '>') {
			# > LABEL
			my ($type,$name,$lang) = split(/\s+/, $line, 3);
			$type = lc($type);

			# Handle the label types.
			if ($type eq 'begin') {
				# The BEGIN statement.
				$self->debug ("Found the BEGIN Statement.");
				$type  = 'topic';
				$name = '__begin__';
			}
			if ($type eq 'topic') {
				# Starting a new topic.
				$self->debug ("Set topic to $name.");
				$ontrig = '';
				$topic = $name;
			}
			if ($type eq 'object') {
				# Only try to parse a language we support.
				$ontrig = '';
				if (not defined $lang) {
					$self->issue ("Trying to parse unknown programming language at $fname line $lineno.");
				}
				elsif ($lang !~ /^perl$/i) {
					$self->debug ("Skipping object of language $lang: not known by interpreter, at $fname line $lineno.");
					$objname = '';
					$inobj = 1;
					next;
				}
				$self->debug ("Attempting to parse object named $name.");
				$objbuf = "sub RSOBJ_$name {\n";
				$objname = $name;
				$inobj = 1;
			}
		}
		elsif ($cmd eq '<') {
			# < LABEL
			my $type = $line;

			if ($type eq 'begin' || $type eq 'topic') {
				$self->debug ("End topic label.");
				$topic = 'random';
			}
			elsif ($type eq 'object') {
				$self->debug ("End object label.");
				$inobj = 0;
			}
		}
		elsif ($cmd eq '+') {
			# + TRIGGER
			$self->debug ("\tTrigger pattern: $line");
			if (length $isThat) {
				$self->{thats}->{$topic}->{$isThat}->{$line} = {};
			}
			else {
				$self->{topics}->{$topic}->{$line} = {};
			}
			$ontrig = $line;
			$repcnt = 0;
			$concnt = 0;
		}
		elsif ($cmd eq '-') {
			# - REPLY
			if ($ontrig eq '') {
				$self->issue ("Response found before trigger at $fname line $lineno.");
				next;
			}
			$self->debug ("\tResponse: $line");
			if (length $isThat) {
				$self->{thats}->{$topic}->{$isThat}->{$ontrig}->{reply}->{$repcnt} = $line;
			}
			else {
				$self->{topics}->{$topic}->{$ontrig}->{reply}->{$repcnt} = $line;
			}
			$repcnt++;
		}
		elsif ($cmd eq '%') {
			# % PREVIOUS
			$self->debug ("\t% Previous pattern: $line");
			# This was handled above.
		}
		elsif ($cmd eq '^') {
			# ^ CONTINUE
			# This should've been handled above...
		}
		elsif ($cmd eq '@') {
			# @ REDIRECT
			$self->debug ("\tRedirect the response to $line");
			if (length $isThat) {
				$self->{thats}->{$topic}->{$isThat}->{$ontrig}->{redirect} = $line;
			}
			else {
				$self->{topics}->{$topic}->{$ontrig}->{redirect} = $line;
			}
		}
		elsif ($cmd eq '*') {
			# * CONDITION
			$self->debug ("\tAdding condition.");
			if (length $isThat) {
				$self->{thats}->{$topic}->{$isThat}->{$ontrig}->{condition}->{$concnt} = $line;
			}
			else {
				$self->{topics}->{$topic}->{$ontrig}->{condition}->{$concnt} = $line;
			}
			$concnt++;
		}
		else {
			$self->issue ("Unrecognized command \"$cmd\" at $fname line $lineno.");
			next;
		}
	}
}

sub sortReplies {
	my $self = shift;
	my $thats = shift || 'no';

	# Make this method dynamic: allow it to sort both triggers and %previous.
	# To that end we need to make some more references.
	my $triglvl = {};
	my $sortlvl = 'sorted';
	if ($thats eq 'thats') {
		$triglvl = $self->{thats};
		$sortlvl = 'sortsthat';
	}
	else {
		$triglvl = $self->{topics};
	}

	$self->debug ("Sorting triggers...");

	# Loop through all the topics.
	foreach my $topic (keys %{$triglvl}) {
		$self->debug ("\tAnalyzing topic $topic");

		# Create a priority map.
		my $prior = {
			0 => [], # Default
		};
		foreach my $trig (keys %{$triglvl->{$topic}}) {
			if ($trig =~ /\{weight=(\d+)\}/i) {
				my $weight = $1;

				if (!exists $prior->{$weight}) {
					$prior->{$weight} = [];
				}

				push (@{$prior->{$weight}}, $trig);
			}
			else {
				push (@{$prior->{0}}, $trig);
			}
		}

		# Keep a running list of sorted triggers for this topic.
		my @running = ();

		# Sort them by priority.
		foreach my $p (sort { $b <=> $a } keys %{$prior}) {
			$self->debug ("\tSorting triggers with priority $p.");

			# Loop through and categorize these triggers.
			my $track = {
				atomic => {}, # Sort by # of whole words
				option => {}, # Sort optionals by # of words
				wild   => {}, # Sort wildcards by # of words
				star   => [], # Triggers of just *
			};

			foreach my $trig (@{$prior->{$p}}) {
				if ($trig =~ /\*/) {
					# Wildcards included.
					my @words = split(/\s+/, $trig);
					my $cnt = scalar(@words);
					if ($cnt > 1) {
						if (!exists $track->{wild}->{$cnt}) {
							$track->{wild}->{$cnt} = [];
						}
						push (@{$track->{wild}->{$cnt}}, $trig);
					}
					else {
						push (@{$track->{star}}, $trig);
					}
				}
				elsif ($trig =~ /\[(.+?)\]/) {
					# Optionals included.
					my @words = split(/\s+/, $trig);
					my $cnt = scalar(@words);
					if (!exists $track->{option}->{$cnt}) {
						$track->{option}->{$cnt} = [];
					}
					push (@{$track->{option}->{$cnt}}, $trig);
				}
				else {
					# Totally atomic.
					my @words = split(/\s+/, $trig);
					my $cnt = scalar(@words);
					if (!exists $track->{atomic}->{$cnt}) {
						$track->{atomic}->{$cnt} = [];
					}
					push (@{$track->{atomic}->{$cnt}}, $trig);
				}
			}

			# Add this group to the sort list.
			foreach my $i (sort { $b <=> $a } keys %{$track->{atomic}}) {
				push (@running,@{$track->{atomic}->{$i}});
			}
			foreach my $i (sort { $b <=> $a } keys %{$track->{option}}) {
				push (@running,@{$track->{option}->{$i}});
			}
			foreach my $i (sort { $b <=> $a } keys %{$track->{wild}}) {
				push (@running,@{$track->{wild}->{$i}});
			}
			push (@running,@{$track->{star}});
		}

		# Save this topic's sorted list.
		$self->{$sortlvl}->{$topic} = [ @running ];
	}

	# Also sort that's.
	if ($thats ne 'thats') {
		$self->sortReplies ('thats');
	}
}

################################################################################
## Configuration Methods                                                      ##
################################################################################

sub setSubroutine {
	my ($self,$name,$sub) = @_;

	$self->{objects}->{$name} = $sub;
	return 1;
}

sub setGlobal {
	my ($self,%data) = @_;

	foreach my $key (keys %data) {
		foreach my $res (@{$self->{reserved}}) {
			if ($res eq $key) {
				$self->issue ("Can't reset global $key: reserved variable name!");
				next;
			}
			$self->{$key} = $data{$key};
		}
	}

	return 1;
}

sub setVariable {
	my ($self,%data) = @_;

	foreach my $key (keys %data) {
		$self->{bot}->{$key} = $data{$key};
	}

	return 1;
}

sub setSubstitution {
	my ($self,%data) = @_;

	foreach my $key (keys %data) {
		$self->{subs}->{$key} = $data{$key};
	}

	return 1;
}

sub setPerson {
	my ($self,%data) = @_;

	foreach my $key (keys %data) {
		$self->{person}->{$key} = $data{$key};
	}

	return 1;
}

sub setUservar {
	my ($self,$user,%data) = @_;

	foreach my $key (keys %data) {
		$self->{client}->{$user}->{$key} = $data{$key};
	}

	return 1;
}

sub getUservars {
	my $self = shift;
	my $user = shift || '';

	if (length $user) {
		return $self->{client}->{$user};
	}
	else {
		return $self->{client};
	}
}

sub clearUservars {
	my $self = shift;
	my $user = shift || '';

	if (length $user) {
		foreach my $var (keys %{$self->{client}->{$user}}) {
			delete $self->{client}->{$user}->{$var};
		}
		delete $self->{client}->{$user};
	}
	else {
		foreach my $client (keys %{$self->{client}}) {
			foreach my $var (keys %{$self->{client}->{$client}}) {
				delete $self->{client}->{$client}->{$var};
			}
			delete $self->{client}->{$client};
		}
	}

	return 1;
}

################################################################################
## Interaction Methods                                                        ##
################################################################################

sub reply {
	my ($self,$user,$msg) = @_;

	$self->debug ("Get reply to [$user] $msg");

	# Format their message.
	$msg = $self->_formatMessage ($msg);

	my $reply = '';

	# If the BEGIN statement exists, consult it first.
	if (exists $self->{topics}->{__begin__}->{request}) {
		# Get a response.
		my $begin = $self->_getreply ($user,'request',
			context => 'begin',
			step    => 0, # Recursion redundancy counter
		);

		# Okay to continue?
		if ($begin =~ /\{ok\}/i) {
			$reply = $self->_getreply ($user,$msg,
				context => 'normal',
				step    => 0,
			);
			$begin =~ s/\{ok\}/$reply/ig;
		}

		$reply = $begin;

		# Run more tag substitutions.
		$reply = $self->processTags ($user,$msg,$reply,[],[]);
	}
	else {
		# Just continue then.
		$reply = $self->_getreply ($user,$msg,
			context => 'normal',
			step    => 0,
		);
	}

	# Save their reply history.
	unshift (@{$self->{client}->{$user}->{__history__}->{input}}, $msg);
	while (scalar @{$self->{client}->{$user}->{__history__}->{input}} > 9) {
		pop (@{$self->{client}->{$user}->{__history__}->{input}});
	}

	unshift (@{$self->{client}->{$user}->{__history__}->{reply}}, $reply);
	while (scalar @{$self->{client}->{$user}->{__history__}->{reply}} > 9) {
		pop (@{$self->{client}->{$user}->{__history__}->{reply}});
	}

	return $reply;
}

sub _getreply {
	my ($self,$user,$msg,%tags) = @_;

	# Avoid deep recursion.
	if ($tags{step} > $self->{depth}) {
		$self->issue ("ERR: Deep Recursion Detected!");
		return "ERR: Deep Recursion Detected!";
	}

	# Need to sort replies?
	if (scalar keys %{$self->{sorted}} == 0) {
		$self->issue ("ERR: You never called sortReplies()! Start doing that from now on!");
		$self->sortReplies();
	}

	# Collect info on this user if we have it.
	my $topic = 'random';
	my @stars = ();
	my @thatstars = (); # For %previous's.
	my $reply = '';
	if (exists $self->{client}->{$user}) {
		$topic = $self->{client}->{$user}->{topic};
	}
	else {
		$self->{client}->{$user}->{topic} = 'random';
	}

	# Are we in the BEGIN Statement?
	if ($tags{context} eq 'begin') {
		# Imply some defaults.
		$topic = '__begin__';
	}

	# Track this user's history.
	if (!exists $self->{client}->{$user}->{__history__}) {
		$self->{client}->{$user}->{__history__}->{input} = [
			'undefined', 'undefined', 'undefined', 'undefined',
			'undefined', 'undefined', 'undefined', 'undefined',
			'undefined',
		];
		$self->{client}->{$user}->{__history__}->{reply} = [
			'undefined', 'undefined', 'undefined', 'undefined',
			'undefined', 'undefined', 'undefined', 'undefined',
			'undefined',
		];
	}

	# Create a pointer for the matched data (be it %previous or +trigger).
	my $matched = {};
	my $foundMatch = 0;

	# See if there are any %previous's in this topic.
	if (exists $self->{sortsthat}->{$topic}) {
		$self->debug ("There's a %previous in this topic");

		# Do we have history yet?
		if (scalar @{$self->{client}->{$user}->{__history__}->{reply}} > 0) {
			my $lastReply = $self->{client}->{$user}->{__history__}->{reply}->[0];

			# Format the bot's last reply the same as the human's.
			$lastReply = $self->_formatMessage ($lastReply);

			$self->debug ("lastReply: $lastReply");

			# See if we find a match.
			foreach my $trig (@{$self->{sortsthat}->{$topic}}) {
				my $botside = $self->_reply_regexp ($user,$trig);

				$self->debug ("Try to match lastReply to $botside");

				# Look for a match.
				if ($lastReply =~ /^$botside$/i) {
					# Found a match! See if our message is correct too.
					(@thatstars) = ($lastReply =~ /^$botside$/i);
					foreach my $subtrig (keys %{$self->{thats}->{$topic}->{$trig}}) {
						my $humanside = $self->_reply_regexp ($user,$subtrig);

						$self->debug ("Now try to match $msg to $humanside");

						if ($msg =~ /^$humanside$/i) {
							$matched = $self->{thats}->{$topic}->{$trig}->{$subtrig};
							$foundMatch = 1;

							# Get the stars.
							(@stars) = ($msg =~ /^$humanside$/i);
							last;
						}
					}
				}
			}
		}
	}

	# Search their topic for a match to their trigger.
	if (not $foundMatch) {
		foreach my $trig (@{$self->{sorted}->{$topic}}) {
			# Process the triggers.
			my $regexp = $self->_reply_regexp ($user,$trig);

			$self->debug ("Trying to match \"$msg\" against $trig");

			if ($msg =~ /^$regexp$/i) {
				$self->debug ("Found a match!");
				$matched = $self->{topics}->{$topic}->{$trig};
				$foundMatch = 1;

				# Get the stars.
				(@stars) = ($msg =~ /^$regexp$/i);
				last;
			}
		}
	}

	for (defined $matched) {
		# See if there are any hard redirects.
		if (exists $matched->{redirect}) {
			$self->debug ("Redirecting us to $matched->{redirect}");
			$reply = $self->_getreply ($user,$matched->{redirect},
				context => $tags{context},
				step    => ($tags{step} + 1),
			);
			last;
		}

		# Check the conditionals.
		if (exists $matched->{condition}) {
			$self->debug ("Checking conditionals");
			for (my $i = 0; exists $matched->{condition}->{$i}; $i++) {
				my ($cond,$potreply) = split(/\s*=>\s*/, $matched->{condition}->{$i}, 2);
				my ($left,$eq,$right) = ($cond =~ /^(.+?)\s+(==|eq|\!=|ne|\<\>|\<|\<=|\>|\>=)\s+(.+?)$/i);

				$self->debug ("\tLeft: $left; EQ: $eq; Right: $right");

				# Process tags on all of these.
				$left = $self->processTags ($user,$msg,$left,[@stars],[@thatstars]);
				$right = $self->processTags ($user,$msg,$right,[@stars],[@thatstars]);

				$self->debug ("\t\tCheck if \"$left\" $eq \"$right\"");

				# Validate the expression.
				my $match = 0;
				if ($eq eq 'eq' || $eq eq '==') {
					if ($left eq $right) {
						$match = 1;
					}
				}
				elsif ($eq eq 'ne' || $eq eq '!=' || $eq eq '<>') {
					if ($left ne $right) {
						$match = 1;
					}
				}
				elsif ($eq eq '<') {
					if ($left < $right) {
						$match = 1;
					}
				}
				elsif ($eq eq '<=') {
					if ($left <= $right) {
						$match = 1;
					}
				}
				elsif ($eq eq '>') {
					if ($left > $right) {
						$match = 1;
					}
				}
				elsif ($eq eq '>=') {
					if ($left >= $right) {
						$match = 1;
					}
				}

				if ($match) {
					# Condition is true.
					$reply = $potreply;
					last;
				}
			}
		}
		last if length $reply > 0;

		# Process weights in the replies.
		my @bucket = ();
		$self->debug ("Processing responses to this trigger.");
		for (my $rep = 0; exists $matched->{reply}->{$rep}; $rep++) {
			my $text = $matched->{reply}->{$rep};
			my $weight = 1;
			if ($text =~ /{weight=(\d+)\}/i) {
				$weight = $1;
				if ($weight <= 0) {
					$weight = 1;
					$self->issue ("Can't have a weight < 0!");
				}
			}
			for (my $i = 0; $i < $weight; $i++) {
				push (@bucket,$text);
			}
		}

		# Get a random reply.
		$reply = $bucket [ int(rand(scalar(@bucket))) ];
		last;
	}

	# Still no reply?
	if ($foundMatch == 0) {
		$reply = "ERR: No Reply Matched";
	}
	elsif (length $reply == 0) {
		$reply = "ERR: No Reply Found";
	}

	$self->debug ("Reply: $reply");

	# Process tags for the BEGIN Statement.
	if ($tags{context} eq 'begin') {
		if ($reply =~ /\{topic=(.+?)\}/i) {
			# Set the user's topic.
			$self->debug ("Topic set to $1");
			$self->{client}->{$user}->{topic} = $1;
			$reply =~ s/\{topic=(.+?)\}//ig;
		}
		while ($reply =~ /<set (.+?)=(.+?)>/i) {
			# Set a user variable.
			$self->debug ("Set uservar $1 => $2");
			$self->{client}->{$user}->{$1} = $2;
			$reply =~ s/<set (.+?)=(.+?)>//i;
		}
	}
	else {
		# Process more tags if not in BEGIN.
		$reply = $self->processTags($user,$msg,$reply,[@stars],[@thatstars]);
	}

	return $reply;
}

sub _reply_regexp {
	my ($self,$user,$regexp) = @_;

	$regexp =~ s/\*/(.+?)/ig;       # Convert * into (.+?)
	$regexp =~ s/\{weight=\d+\}//ig; # Remove {weight} tags.
	while ($regexp =~ /\[(.+?)\]/i) { # Optionals
		my @parts = split(/\|/, $1);
		my @new = ();
		foreach my $p (@parts) {
			$p = '\s*' . $p . '\s*';
			push (@new,$p);
		}
		push (@new,'\s*');
		my $rep = '(?:' . join ("|",@new) . ")";
		$regexp =~ s/\s*\[(.+?)\]\s*/$rep/i;
	}

	# Filter in arrays.
	while ($regexp =~ /\@(.+?)\b/) {
		my $name = $1;
		my $rep = '';
		if (exists $self->{arrays}->{$name}) {
			$rep = '(?:' . join ("|",@{$self->{arrays}->{$name}}) . ')';
		}
		$regexp =~ s/\@(.+?)\b/$rep/i;
	}

	# Filter in bot variables.
	while ($regexp =~ /<bot (.+?)>/i) {
		my $var = $1;
		my $rep = '';
		if (exists $self->{bot}->{$var}) {
			$rep = $self->{bot}->{$var};
			$rep =~ s/[^A-Za-z0-9 ]//ig;
			$rep = lc($rep);
		}
		$regexp =~ s/<bot (.+?)>/$rep/i;
	}

	# Filter input tags.
	while ($regexp =~ /<input([0-9])>/i) {
		my $index = $1;
		my (@arrInput) = @{$self->{client}->{$user}->{__history__}->{input}};
		unshift (@arrInput,'');
		my $line = $arrInput[$index];
		$line = $self->_formatMessage ($line);
		$regexp =~ s/<input$index>/$line/ig;
	}
	while ($regexp =~ /<reply([0-9])>/i) {
		my $index = $1;
		my (@arrReply) = @{$self->{client}->{$user}->{__history__}->{reply}};
		unshift (@arrReply,'');
		my $line = $arrReply[$index];
		$line = $self->_formatMessage ($line);
		$regexp =~ s/<reply$index>/$line/ig;
	}

	return $regexp;
}

sub processTags {
	my ($self,$user,$msg,$reply,$st,$bst) = @_;
	my (@stars) = (@{$st});
	my (@botstars) = (@{$bst});
	unshift (@stars,"");
	unshift (@botstars,"");
	if (scalar(@stars) == 1) {
		push (@stars,'undefined');
	}
	if (scalar(@botstars) == 1) {
		push (@botstars,'undefined');
	}

	my (@arrInput) = @{$self->{client}->{$user}->{__history__}->{input}};
	my (@arrReply) = @{$self->{client}->{$user}->{__history__}->{reply}};

	my $lastInput = $arrInput[0] || 'undefined';
	my $lastReply = $arrReply[0] || 'undefined';
	unshift(@arrInput,'');
	unshift(@arrReply,'');

	# Tag Shortcuts.
	$reply =~ s~<person>~{person}<star>{/person}~ig;
	$reply =~ s~<\@>~{\@<star>}~ig;
	$reply =~ s~<formal>~{formal}<star>{/formal}~ig;
	$reply =~ s~<sentence>~{sentence}<star>{/sentence}~ig;
	$reply =~ s~<uppercase>~{uppercase}<star>{/uppercase}~ig;
	$reply =~ s~<lowercase>~{lowercase}<star>{/lowercase}~ig;

	# Quick tags.
	$reply =~ s/\{weight=(\d+)\}//ig; # Remove leftover {weight}s
	if (scalar(@stars) > 0) {
		$reply =~ s/<star>/$stars[1]/ig if defined $stars[1];
		$reply =~ s/<star(\d+)>/(defined $stars[$1] ? $stars[$1] : '')/ieg;
	}
	if (scalar(@botstars) > 0) {
		$reply =~ s/<botstar>/$botstars[1]/ig;
		$reply =~ s/<botstar(\d+)>/(defined $botstars[$1] ? $botstars[$1] : '')/ieg;
	}
	$reply =~ s/<input>/$lastInput/ig;
	$reply =~ s/<reply>/$lastReply/ig;
	$reply =~ s/<input([1-9])>/$arrInput[$1]/ig;
	$reply =~ s/<reply([1-9])>/$arrReply[$1]/ig;
	$reply =~ s/<id>/$user/ig;
	$reply =~ s/\\s/ /ig;
	$reply =~ s/\\n/\n/ig;
	$reply =~ s/\\/\\/ig;
	$reply =~ s/\\#/#/ig;

	while ($reply =~ /\{person\}(.+?)\{\/person\}/i) {
		my $person = $1;
		$person = $self->_personSub ($person);
		$reply =~ s/\{person\}(.+?)\{\/person\}/$person/i;
	}
	while ($reply =~ /\{formal\}(.+?)\{\/formal\}/i) {
		my $formal = $1;
		$formal = $self->_stringUtil ('formal',$formal);
		$reply =~ s/\{formal\}(.+?)\{\/formal\}/$formal/i;
	}
	while ($reply =~ /\{sentence\}(.+?)\{\/sentence\}/i) {
		my $sentence = $1;
		$sentence = $self->_stringUtil ('sentence',$sentence);
		$reply =~ s/\{sentence\}(.+?)\{\/sentence\}/$sentence/i;
	}
	while ($reply =~ /\{uppercase\}(.+?)\{\/uppercase\}/i) {
		my $upper = $1;
		$upper = $self->_stringUtil ('upper',$upper);
		$reply =~ s/\{uppercase\}(.+?)\{\/uppercase\}/$upper/i;
	}
	while ($reply =~ /\{lowercase\}(.+?)\{\/lowercase\}/i) {
		my $lower = $1;
		$lower = $self->_stringUtil ('lower',$lower);
		$reply =~ s/\{lowercase\}(.+?)\{\/lowercase\}/$lower/i;
	}
	while ($reply =~ /\{random\}(.+?)\{\/random\}/i) {
		my $rand = $1;
		my $output = '';
		if ($rand =~ /\|/) {
			my @tmp = split(/\|/, $rand);
			$output = $tmp [ int(rand(scalar(@tmp))) ];
		}
		else {
			my @tmp = split(/\s+/, $rand);
			$output = $tmp [ int(rand(scalar(@tmp))) ];
		}
		$reply =~ s/\{random\}(.+?)\{\/random\}/$output/i;
	}
	while ($reply =~ /<bot (.+?)>/i) {
		my $val = (exists $self->{bot}->{$1} ? $self->{bot}->{$1} : 'undefined');
		$reply =~ s/<bot (.+?)>/$val/i;
	}
	while ($reply =~ /<env (.+?)>/i) {
		my $var = $1;
		my $val = '';
		my $reserved = 0;
		foreach my $res (@{$self->{reserved}}) {
			if ($res eq $var) {
				$reserved = 1;
			}
		}
		if (not $reserved) {
			$val = (exists $self->{$var} ? $self->{$var} : 'undefined');
		}
		$reply =~ s/<env (.+?)>/$val/i;
	}
	while ($reply =~ /\{\!(.+?)\}/i) {
		# Just stream this back through.
		$self->stream ("! $1");
		$reply =~ s/\{\!(.+?)\}//i;
	}
	while ($reply =~ /<set (.+?)=(.+?)>/i) {
		# Set a user variable.
		$self->debug ("Set uservar $1 => $2");
		$self->{client}->{$user}->{$1} = $2;
		$reply =~ s/<set (.+?)=(.+?)>//i;
	}
	while ($reply =~ /<(add|sub|mult|div) (.+?)=(.+?)>/i) {
		# Mathematic modifiers.
		my $mod = lc($1);
		my $var = $2;
		my $value = $3;
		my $output = '';

		# Initialize the variable?
		if (!exists $self->{client}->{$user}->{$var}) {
			$self->{client}->{$user}->{$var} = 0;
		}

		# Only modify numeric variables.
		if ($self->{client}->{$user}->{$var} !~ /^[0-9\-\.]+$/) {
			$output = "[ERR: Can't Modify Non-Numeric Variable $var]";
		}
		elsif ($value =~ /^[^0-9\-\.]$/) {
			$output = "[ERR: Math Can't \"$mod\" Non-Numeric Value $value]";
		}
		else {
			# Modify the variable.
			if ($mod eq 'add') {
				$self->{client}->{$user}->{$var} += $value;
			}
			elsif ($mod eq 'sub') {
				$self->{client}->{$user}->{$var} -= $value;
			}
			elsif ($mod eq 'mult') {
				$self->{client}->{$user}->{$var} *= $value;
			}
			elsif ($mod eq 'div') {
				# Don't divide by zero.
				if ($value == 0) {
					$output = "[ERR: Can't Divide By Zero]";
				}
				else {
					$self->{client}->{$user}->{$var} /= $value;
				}
			}
		}

		$reply =~ s/<(add|sub|mult|div) (.+?)=(.+?)>/$output/i;
	}
	while ($reply =~ /<get (.+?)>/i) {
		my $val = (exists $self->{client}->{$user}->{$1} ? $self->{client}->{$user}->{$1} : 'undefined');
		$reply =~ s/<get (.+?)>/$val/i;
	}
	if ($reply =~ /\{topic=(.+?)\}/i) {
		# Set the user's topic.
		$self->debug ("Topic set to $1");
		$self->{client}->{$user}->{topic} = $1;
		$reply =~ s/\{topic=(.+?)\}//ig;
	}
	while ($reply =~ /\{\@(.+?)\}/i) {
		my $at = $1;
		$at =~ s/^\s+//ig;
		$at =~ s/\s+$//ig;
		my $subreply = $self->_getreply ($user,$at,
			context => 'normal',
			step    => 0,
		);
		$reply =~ s/\{\@(.+?)\}/$subreply/i;
	}
	while ($reply =~ /<call>(.+?)<\/call>/i) {
		my ($obj,@args) = split(/\s+/, $1);
		my $output = '';
		if (exists $self->{objects}->{$obj}) {
			$output = &{$self->{objects}->{$obj}} ($self,@args) || '';
		}
		else {
			$output = '[ERR: Object Not Found]';
		}
		$reply =~ s/<call>(.+?)<\/call>/$output/i;
	}

	return $reply;
}

sub _formatMessage {
	my ($self,$string) = @_;

	# Lowercase it.
	$string = lc($string);

	# Run substitutions on it.
	my @words = split(/\s+/, $string);
	my @new = ();
	foreach my $word (@words) {
		if (exists $self->{subs}->{$word}) {
			$word = $self->{subs}->{$word};
		}
		push (@new,$word);
	}

	# Reconstruct.
	my $sanitized = join (" ",@new);

	# Format punctuation.
	$sanitized =~ s/[^A-Za-z0-9 ]//g;
	$sanitized =~ s/^\s+//g;
	$sanitized =~ s/\s+$//g;

	return $sanitized;
}

sub _stringUtil {
	my ($self,$type,$string) = @_;

	if ($type eq 'formal') {
		$string =~ s~\b(\w+)\b~\L\u$1\E~ig;
	}
	elsif ($type eq 'sentence') {
		$string =~ s~\b(\w)(.*?)(\.|\?|\!|$)~\u$1\L$2$3\E~ig;
	}
	elsif ($type eq 'upper') {
		$string = uc($string);
	}
	elsif ($type eq 'lower') {
		$string = lc($string);
	}

	return $string;
}

sub _personSub {
	my ($self,$string) = @_;

	my @words = split(/\s/, $string);
	my @new = ();
	foreach my $word (@words) {
		foreach my $sub (keys %{$self->{person}}) {
			my $re = quotemeta($sub);
			if ($word =~ /$re/i) {
				$word =~ s/$re/$self->{person}->{$sub}/ig;
				last;
			}
		}
		push (@new,$word);
	}

	return join (" ",@new);
}

1;
__END__

=head1 NAME

RiveScript - Rendering Intelligence Very Easily

=head1 SYNOPSIS

  use RiveScript;

  # Create a new RiveScript interpreter.
  my $rs = new RiveScript;

  # Load a directory of replies.
  $rs->loadDirectory ("./replies");

  # Load another file.
  $rs->loadFile ("./more_replies.rs");

  # Stream in some RiveScript code.
  $rs->stream (q~
    + hello bot
    - Hello, human.
  ~);

  # Sort all the loaded replies.
  $rs->sortReplies;

  # Chat with the bot.
  while (1) {
    print "You> ";
    chomp (my $msg = <STDIN>);
    my $reply = $rs->reply ('localuser',$msg);
    print "Bot> $reply\n";
  }

=head1 DESCRIPTION

RiveScript is a simple trigger/response language primarily used for the creation
of chatting robots. It's designed to have an easy-to-learn syntax but provide a
lot of power and flexibility. For more information, visit
http://www.rivescript.com/

=head1 METHODS

=head2 GENERAL

=over 4

=item new (ARGS)

Create a new instance of a RiveScript interpreter. The instance will become its
own "chatterbot," with its own set of responses and user variables. You can pass
in any global variables here. The two standard variables are:

  debug - Turns on debug mode (a LOT of information will be printed to the
          terminal!). Default is 0 (disabled).
  depth - Determines the recursion depth limit when following a trail of replies
          that point to other replies. Default is 50.

It's recommended that if you set any other global variables that you do so by
calling C<setGlobal> or defining it within the RiveScript code. This will avoid
the possibility of overriding reserved globals. Currently, these variable names
are reserved:

  topics  sorted   sortsthat  thats
  arrays  subs     person     client
  bot     objects  reserved

=back

=head2 LOADING AND PARSING

=over 4

=item loadDirectory ($PATH[,@EXTS])

Load a directory full of RiveScript documents. C<$PATH> must be a path to a
directory. C<@EXTS> is optionally an array containing file extensions, including
the dot. By default C<@EXTS> is C<('.rs')>.

Returns true on success, false on failure.

=item loadFile ($PATH)

Load a single RiveScript document. C<$PATH> should be the path to a valid
RiveScript file. Returns true on success; false otherwise.

=item stream ($CODE)

Stream RiveScript code directly into the module. This is for providing RS code
from within the Perl script instead of from an external file. Returns true on
success.

=item sortReplies

Call this method after loading replies to create an internal sort buffer. This
is necessary for trigger matching purposes. If you fail to call this method
yourself, RiveScript will call it once when you request a reply. However, it
will complain loudly about it.

=back

=head2 CONFIGURATION

=over 4

=item setSubroutine ($NAME, $CODEREF)

Manually create a RiveScript object (a dynamic bit of Perl code that can be
provoked in a RiveScript response). C<$NAME> should be a single-word,
alphanumeric string. C<$CODEREF> should be a pointer to a subroutine or an
anonymous sub.

=item setGlobal (%DATA)

Set one or more global variables, in hash form, where the keys are the variable
names and the values are their value. This subroutine will make sure that you
don't override any reserved global variables, and warn if that happens.

This is equivalent to C<! global> in RiveScript code.

=item setVariable (%DATA)

Set one or more bot variables (things that describe your bot's personality).

This is equivalent to C<! var> in RiveScript code.

=item setSubstitution (%DATA)

Set one or more substitution patterns. The keys should be the original word, and
the value should be the word to substitute with it.

  $rs->setSubstitution (
    q{what's}  => 'what is',
    q{what're} => 'what are',
  );

This is equivalent to C<! sub> in RiveScript code.

=item setPerson (%DATA)

Set a person substitution. This is equivalent to C<! person> in RiveScript code.

=item setUservar ($USER,%DATA)

Set a variable for a user. C<$USER> should be their User ID, and C<%DATA> is a
hash containing variable/value pairs.

This is like C<E<lt>setE<gt>> for a specific user.

=item getUservars ([$USER])

Get all the variables about a user. If a username is provided, returns a hash
B<reference> containing that user's information. Else, a hash reference of all
the users and their information is returned.

This is like C<E<lt>getE<gt>> for a specific user or for all users.

=item clearUservars ([$USER])

Clears all variables about C<$USER>. If no C<$USER> is provided, clears all
variables about all users.

=back

=head2 INTERACTION

=over 4

=item reply ($USER,$MESSAGE)

Fetch a response to C<$MESSAGE> from user C<$USER>. RiveScript will take care of
lowercasing, running substitutions, and removing punctuation from the message.

Returns a response from the RiveScript brain.

=back

=head2 INTERNAL

=over 4

=item debug ($MESSAGE) *Internal

Prints a debug message to the terminal. Called from within in debug mode.

=item issue ($MESSAGE) *Internal

Called internally to report an issue (similar to a warning). If debug mode is
active, it will print the issue to STDOUT with a # sign prepended. Otherwise,
the issue is sent to STDERR via C<warn>.

=item parse ($FILENAME, $CODE) *Internal

This method is called internally to parse a file or streamed RiveScript code.
C<$FILENAME> is only there so it can keep internal track of files and line
numbers, in case syntax errors appear.

=item _getreply ($USER,$MSG,%TAGS) *Internal

B<Do NOT call this method yourself.> This method assumes a few things about the
user's input that is taken care of by C<reply()>. There is no reason to call
this method manually.

=item _reply_regexp ($USER,$TRIGGER) *Internal

This method takes a raw trigger C<$TRIGGER> and formats it for a matching
attempt in a regular expression. It removes C<{weight}> tags, processes arrays,
processes bot variables and other tags, and returns something ready for the
regular expression engine.

=item processTags ($USER,$MSG,$REPLY,$STARS,$BOTSTARS) *Internal

Process tags in the bot's response. C<$USER> and C<$MSG> are the values
originally passed to the reply engine. C<$REPLY> is the bot's raw response.
C<$STARS> and C<$BOTSTARS> are array references containing any wildcards matched
in a trigger or C<%Previous> command, respectively. Returns a reply with all the
tags processed.

=item _formatMessage ($STRING) *Internal

Formats a message to prepare it for reply matching. Lowercases the string, runs
substitutions, and sanitizes what's left.

=item _stringUtil ($TYPE,$STRING) *Internal

Runs string modifiers on C<$STRING> (uppercase, lowercase, sentence, formal).

=item _personSub ($STRING) *Internal

Runs person substitutions on C<$STRING>.

=back

=head1 RIVESCRIPT

This interpreter tries its best to follow RiveScript standards. Currently it
supports RiveScript 2.0 documents. A current copy of the RiveScript working
draft is included with this package: see L<RiveScript::WD>.

=head1 ERROR MESSAGES

Most of the Perl warnings that the module will emit are self-explanatory, and
when parsing RiveScript files, file names and line numbers will be given. This
section of the manpage instead outlines error strings that may turn up in
responses to the bot's queries.

=head2 ERR: Deep Recursion Detected!

The deep recursion depth limit has been reached (a response redirected to a
different trigger, which redirected somewhere else, etc.).

How to fix: override the global variable C<depth>. This can be done via
C<setGlobal> or in the RiveScript code:

  ! global depth = 100

=head2 ERR: No Reply Matched

No match was found for the client's message.

How to fix: create a catch-all trigger of just C<*>.

  + *
  - I don't know how to reply to that.

=head2 ERR: No Reply Found

A match to the client's message was found, but no response to it was found. This
might mean you had a set of conditionals after it, and no C<-Reply> to fall back
on, and every conditional returned false.

How to fix: make sure you have at least one C<-Reply> to every C<+Trigger>, even
if you don't expect that the C<-Reply> will ever be used.

=head2 [ERR: Can't Modify Non-Numeric Variable $var]

You called a math tag on a variable, and the current value of the variable
contains something that isn't a number.

How to fix: verify that the variable you're working with is a number. If
necessary, reset the variable via C<E<lt>setE<gt>>.

=head2 [ERR: Math Can't "add" Non-Numeric Value $value]

("add" may also be sub, mult, or div). You tried to run a math function on a
variable, but the value you used wasn't a number.

How to fix: verify that you're adding, subtracting, multiplying, or dividing
using numbers.

=head2 [ERR: Can't Divide By Zero]

A C<E<lt>divE<gt>> tag was found that attempted to divide a variable by zero.

How to fix: make sure your division isn't dividing by zero. If you're using a
variable to provide the divisor, validate that the variable isn't zero by using
a conditional.

  * <get divisor> == 0 => The divisor is zero so I can't do that.
  - <div myvar=<get divisor>>I divided the variable by <get divisor>.

=head2 [ERR: Object Not Found]

RiveScript attempted to call an object that doesn't exist. This may be because a
syntax error in the object prevented Perl from evaluating it, or the object was
written in a different programming language.

How to fix: verify that the called object was loaded properly. You will receive
notifications on the terminal if the object failed to load for any reason.

=head1 SEE ALSO

L<RiveScript::WD> - A current snapshot of the Working Draft that
defines the standards of RiveScript.

L<http://www.rivescript.com/> - The official homepage of RiveScript.

=head1 CHANGES

  1.14  Apr  2 2008
  - Bugfix: If a BEGIN/request trigger didn't exist, RiveScript would not fetch
    any replies for the client's message. Fixed.
  - Bugfix: Tags weren't being re-processed for the text of the BEGIN statement,
    so i.e. {uppercase}{ok}{/uppercase} wasn't working as expected. Fixed.
  - Bugfix: RiveScript wasn't parsing out inline comments properly.
  - Rearranged tag priorities.
  - Optimization: When substituting <star>s in, an added bit of code will insert
    '' (nothing) if the variable is undefined. This prevents Perl warnings that
    occurred frequently with the Eliza brain.
  - Updated the RiveScript Working Draft.

  1.13  Mar 18 2008
  - Included an "rsup" script for upgrading old RiveScript code.
  - Attempted to fix the package for CPAN (1.12 was a broken upload).
  - Bugfix: <bot> didn't have higher priority than <set>, so
    i.e. <set name=<bot name>> wouldn't work as expected. Fixed.

  1.12  Mar 16 2008
  - Initial beta release for a RiveScript 2.00 parser.

=head1 AUTHOR

  Casey Kirsle, http://www.cuvou.com/

=head1 KEYWORDS

bot, chatbot, chatterbot, chatter bot, reply, replies, script, aiml, alpha

=head1 COPYRIGHT AND LICENSE

  RiveScript - Rendering Intelligence Very Easily
  Copyright (C) 2008  Casey Kirsle

  This program is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation; either version 2 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program; if not, write to the Free Software
  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

=cut
