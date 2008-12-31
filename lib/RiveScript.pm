package RiveScript;

use strict;
use warnings;

our $VERSION = '1.18'; # Version of the Perl RiveScript interpreter.
our $SUPPORT = '2.0';  # Which RS standard we support.
our $basedir = (__FILE__ =~ /^(.+?)\.pm$/i ? $1 : '.');

################################################################################
## Constructor and Debug Methods                                              ##
################################################################################

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto || 'RiveScript';

	my $self = {
		debug      => 0,
		debugopts  => {
			verbose => 1,  # Print to the terminal
			file    => '', # Print to a filename
		},
		depth      => 50, # Recursion depth allowed.
		topics     => {}, # Loaded replies under topics
		lineage    => {}, # Keep track of topics that inherit other topics
		sorted     => {}, # Sorted triggers
		sortsthat  => {}, # Sorted %previous's.
		sortedthat => {}, # Sorted triggers that go with %previous's
		thats      => {}, # Reverse mapping for %previous, under topics
		arrays     => {}, # Arrays
		subs       => {}, # Substitutions
		person     => {}, # Person substitutions
		client     => {}, # User variables
		frozen     => {}, # Frozen (backed-up) user variables
		bot        => {}, # Bot variables
		objects    => {}, # Subroutines
		syntax     => {}, # Syntax tracking
		sortlist   => {}, # Sorted lists (i.e. person subs)
		reserved   => [   # Reserved global variable names.
			qw(topics sorted sortsthat sortedthat thats arrays subs person
			client bot objects syntax sortlist reserved debugopts frozen)
		],
		@_,
	};
	bless ($self,$class);

	# See if any additional debug options were provided.
	if (exists $self->{verbose}) {
		$self->{debugopts}->{verbose} = delete $self->{verbose};
	}
	if (exists $self->{debugfile}) {
		$self->{debugopts}->{file} = delete $self->{debugfile};
	}

	$self->debug ("RiveScript $VERSION Initialized");

	return $self;
}

sub debug {
	my ($self,$msg) = @_;
	if ($self->{debug}) {
		# Verbose debugging?
		if ($self->{debugopts}->{verbose}) {
			print "RiveScript: $msg\n";
		}

		# Debugging to a file?
		if (length $self->{debugopts}->{file}) {
			# Get a real quick timestamp.
			my @time = localtime(time());
			my $stamp = join(":",$time[2],$time[1],$time[0]);
			open (WRITE, ">>$self->{debugopts}->{file}");
			print WRITE "[$stamp] RiveScript: $msg\n";
			close (WRITE);
		}
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

	# If a begin.rs file exists, load it first.
	if (-f "$dir/begin.rs") {
		$self->debug ("loadDirectory: Read begin.rs");
		$self->loadFile ("$dir/begin.rs");
	}

	opendir (DIR, $dir);
	foreach my $file (sort { $a cmp $b } readdir(DIR)) {
		next if $file eq '.';
		next if $file eq '..';
		next if $file =~ /\~$/i; # Skip backup files
		next if $file eq 'begin.rs';
		my $badExt = 0;
		foreach (@exts) {
			my $re = quotemeta($_);
			$badExt = 1 unless $file =~ /$re$/;
		}
		next if $badExt;

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
	$code =~ s/([\x0d\x0a])+/\x0a/ig;
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

		$self->debug ("Line: $line (topic: $topic)");

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
			# The "#" format for comments is deprecated.
			if ($line =~ /^#/) {
				$self->issue ("Using the # symbol for comments is deprecated at $fname line $lineno.");
			}
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
		$line =~ s/^.//i;
		$line =~ s/^\s+?//ig;

		# Ignore inline comments if there's a space before and after
		# the // or # symbols.
		my $inline_comment_regexp = "(\\s+\\#\\s+|\\/\\/)";
		$line =~ s/\\\/\//\\\/\\\//g; # Turn \// into \/\/
		if ($cmd eq '+') {
			$inline_comment_regexp = "(\\s\\s\\#|\\/\\/)";
			if ($line =~ /\s\s#/) {
				# Deprecated.
				$self->issue ("Using the # symbol for comments is deprecated at $fname line $lineno.");
			}
		}
		else {
			if ($line =~ /\s#/) {
				# Deprecated.
				$self->issue ("Using the # symbol for comments is deprecated at $fname line $lineno.");
			}
		}
		if ($line =~ /$inline_comment_regexp/) {
			my ($left,$comment) = split(/$inline_comment_regexp/, $line, 2);
			$left =~ s/\s+$//g;
			$line = $left;
		}

		$self->debug ("\tCmd: $cmd");

		# Reset the %previous state if this is a new +Trigger.
		if ($cmd eq '+') {
			$isThat = '';
		}

		# Do a lookahead for ^Continue and %Previous commands.
		for (my $i = ($lp + 1); $i < scalar(@lines); $i++) {
			my $lookahead = $lines[$i];
			$lookahead =~ s/^(\t|\x0a|\x0d|\s)+//g;
			my ($lookCmd) = $lookahead =~ /^(.)/i;
			$lookahead =~ s/^([^\s]+)\s+//i;

			# Only continue if the lookahead line has any data.
			if (defined $lookahead && length $lookahead > 0) {
				# The lookahead command has to be either a % or a ^.
				if ($lookCmd ne '^' && $lookCmd ne '%') {
					#$isThat = '';
					last;
				}

				# If the current command is a +, see if the following command
				# is a % (previous)
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

				# If the current command is a ! and the next command(s) are
				# ^, we'll tack each extension on as a line break (which is
				# useful information for arrays; everything else is gonna ditch
				# this info).
				if ($cmd eq '!') {
					if ($lookCmd eq '^') {
						$self->debug ("\t^ [$lp;$i] $lookahead");
						$line .= "<crlf>$lookahead";
						$self->debug ("\tLine: $line");
					}
					next;
				}

				# If the current command is not a ^ and the line after is
				# not a %, but the line after IS a ^, then tack it onto the
				# end of the current line (this is fine for every other type
				# of command that doesn't require special treatment).
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
		}

		if ($cmd eq '!') {
			# ! DEFINE
			my ($left,$value) = split(/\s*=\s*/, $line, 2);
			my ($type,$var) = split(/\s+/, $left, 2);
			$ontrig = '';
			$self->debug ("\t! DEFINE");

			# Remove line breaks unless this is an array.
			if ($type ne 'array') {
				$value =~ s/<crlf>//ig;
			}

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

				# Did this have multiple lines?
				my @parts = split(/<crlf>/i, $value);
				$self->debug("Array lines: " . join(";",@parts));

				# Process each line of array data.
				my @fields = ();
				foreach my $val (@parts) {
					# Split at pipes or spaces?
					if ($val =~ /\|/) {
						push (@fields,split(/\|/, $val));
					}
					else {
						push (@fields,split(/\s+/, $val));
					}
				}

				# Convert any remaining \s escape codes into spaces.
				foreach my $f (@fields) {
					$f =~ s/\\s/ /ig;
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
			my ($type,$name,@fields) = split(/\s+/, $line);
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

				# Does this topic inherit another one?
				if (scalar(@fields) >= 2 && $fields[0] =~ /^inherits$/i) {
					# Inheriting multiple topics and the topics must be separated
					# by spaces.
					for (my $i = 1; $i < scalar(@fields); $i++) {
						my $inherits = $fields[$i];
						$self->{lineage}->{$name}->{$inherits} = 1;
					}
				}
			}
			if ($type eq 'object') {
				# If a field was provided, it should be the programming language.
				my $lang = (scalar(@fields) ? $fields[0] : undef);

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
				$self->debug ("\t\tInitializing the \%previous structure.");
				$self->{thats}->{$topic}->{$isThat}->{$line} = {};
			}
			else {
				$self->{topics}->{$topic}->{$line} = {};
				$self->{syntax}->{$topic}->{$line}->{ref} = "$fname line $lineno";
				$self->debug ("\t\tSaved to \$self->{topics}->{$topic}->{$line}: "
					. "$self->{topics}->{$topic}->{$line}");
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
				$self->{syntax}->{$topic}->{$ontrig}->{reply}->{$repcnt}->{ref} = "$fname line $lineno";
				$self->debug ("\t\tSaved to \$self->{topics}->{$topic}->{$ontrig}->{reply}->{$repcnt}: "
					. "$self->{topics}->{$topic}->{$ontrig}->{reply}->{$repcnt}");
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

		# Collect a list of all the triggers we're going to need to
		# worry about. If this topic inherits another topic, we need to
		# recursively add those to the list.
		my @alltrig = $self->_topicTriggers($topic,$triglvl,0);
		#foreach my $trig (keys %{$triglvl->{$topic}}) {
		foreach my $trig (@alltrig) {
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
				alpha  => {}, # Sort alpha wildcards by # of words
				number => {}, # Sort numeric wildcards by # of words
				wild   => {}, # Sort wildcards by # of words
				pound  => [], # Triggers of just #
				under  => [], # Triggers of just _
				star   => [], # Triggers of just *
			};

			foreach my $trig (@{$prior->{$p}}) {
				if ($trig =~ /\_/) {
					# Alphabetic wildcard included.
					my @words = split(/[\s\*\#\_]+/, $trig);
					my $cnt = scalar(@words);
					if ($cnt > 1) {
						if (!exists $track->{alpha}->{$cnt}) {
							$track->{alpha}->{$cnt} = [];
						}
						push (@{$track->{alpha}->{$cnt}}, $trig);
					}
					else {
						push (@{$track->{under}}, $trig);
					}
				}
				elsif ($trig =~ /\#/) {
					# Numeric wildcard included.
					my @words = split(/[\s\*\#\_]/, $trig);
					my $cnt = scalar(@words);
					if ($cnt > 1) {
						if (!exists $track->{number}->{$cnt}) {
							$track->{number}->{$cnt} = [];
						}
						push (@{$track->{number}->{$cnt}}, $trig);
					}
					else {
						push (@{$track->{pound}}, $trig);
					}
				}
				elsif ($trig =~ /\*/) {
					# Wildcards included.
					my @words = split(/[\s\*\#\_]/, $trig);
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
					my @words = split(/[\s\*\#\_]/, $trig);
					my $cnt = scalar(@words);
					if (!exists $track->{option}->{$cnt}) {
						$track->{option}->{$cnt} = [];
					}
					push (@{$track->{option}->{$cnt}}, $trig);
				}
				else {
					# Totally atomic.
					my @words = split(/[\s\*\#\_]/, $trig);
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
			foreach my $i (sort { $b <=> $a } keys %{$track->{alpha}}) {
				push (@running,@{$track->{alpha}->{$i}});
			}
			foreach my $i (sort { $b <=> $a } keys %{$track->{number}}) {
				push (@running,@{$track->{number}->{$i}});
			}
			foreach my $i (sort { $b <=> $a } keys %{$track->{wild}}) {
				push (@running,@{$track->{wild}->{$i}});
			}
			push (@running,@{$track->{under}});
			push (@running,@{$track->{pound}});
			push (@running,@{$track->{star}});
		}

		# Save this topic's sorted list.
		$self->{$sortlvl}->{$topic} = [ @running ];
	}

	# Also sort that's.
	if ($thats ne 'thats') {
		# This will sort the %previous lines to best match the bot's last reply.
		$self->sortReplies ('thats');

		# If any of those %previous's had more than one +trigger for them, this
		# will sort all those +trigger's to pair back the best human interaction.
		$self->sortThatTriggers;

		# Also sort both kinds of substitutions.
		$self->sortList ('subs', keys %{$self->{subs}});
		$self->sortList ('person', keys %{$self->{person}});
	}
}

sub sortThatTriggers {
	my ($self) = @_;

	# Usage case: if you have more than one +trigger with the same %previous,
	# this will create a sort buffer for all those +trigger's.
	# Ex:
	#
	# + how [are] you [doing]
	# - I'm doing great, how are you?
	# - Good -- how are you?
	# - Fine, how are you?
	#
	# + [*] @good [*]
	# % * how are you
	# - That's good. :-)
	#
	# 	# // TODO: why isn't this ever called?
	# + [*] @bad [*]
	# % * how are you
	# - Aww. :-( What's the matter?
	#
	# + *
	# % * how are you
	# - I see...

	# The sort buffer for this.
	$self->{sortedthat} = {};
	# Eventual structure:
	# $self->{sortedthat} = {
	#	random => {
	#		'* how are you' => [
	#			'[*] @good [*]',
	#			'[*] @bad [*]',
	#			'*',
	#		],
	#	},
	# };

	$self->debug ("Sorting reverse triggers for %previous groups...");

	foreach my $topic (keys %{$self->{thats}}) {
		# Create a running list of the sort buffer for this topic.
		my @running = ();

		$self->debug ("Sorting the 'that' triggers for topic $topic");
		foreach my $that (keys %{$self->{thats}->{$topic}}) {
			$self->debug ("Sorting triggers that go with the 'that' of \"$that\"");
			# Loop through and categorize these triggers.
			my $track = {
				atomic => {}, # Sort by # of whole words
				option => {}, # Sort optionals by # of words
				alpha  => {}, # Sort letters by # of words
				number => {}, # Sort numbers by # of words
				wild   => {}, # Sort wildcards by # of words
				pound  => [], # Triggers of just #
				under  => [], # Triggers of just _
				star   => [], # Triggers of just *
			};

			# Loop through all the triggers for this %previous.
			foreach my $trig (keys %{$self->{thats}->{$topic}->{$that}}) {
				if ($trig =~ /\_/) {
					# Alphabetic wildcard included.
					my @words = split(/[\s\*\#\_]/, $trig);
					my $cnt = scalar(@words);
					if ($cnt > 1) {
						if (!exists $track->{alpha}->{$cnt}) {
							$track->{alpha}->{$cnt} = [];
						}
						push (@{$track->{alpha}->{$cnt}}, $trig);
					}
					else {
						push (@{$track->{under}}, $trig);
					}
				}
				elsif ($trig =~ /\#/) {
					# Numeric wildcard included.
					my @words = split(/[\s\*\#\_]/, $trig);
					my $cnt = scalar(@words);
					if ($cnt > 1) {
						if (!exists $track->{number}->{$cnt}) {
							$track->{number}->{$cnt} = [];
						}
						push (@{$track->{number}->{$cnt}}, $trig);
					}
					else {
						push (@{$track->{pound}}, $trig);
					}
				}
				elsif ($trig =~ /\*/) {
					# Wildcards included.
					my @words = split(/[\s\*\#\_]/, $trig);
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
					my @words = split(/[\s\*\#\_]/, $trig);
					my $cnt = scalar(@words);
					if (!exists $track->{option}->{$cnt}) {
						$track->{option}->{$cnt} = [];
					}
					push (@{$track->{option}->{$cnt}}, $trig);
				}
				else {
					# Totally atomic.
					my @words = split(/[\s\*\#\_]/, $trig);
					my $cnt = scalar(@words);
					if (!exists $track->{atomic}->{$cnt}) {
						$track->{atomic}->{$cnt} = [];
					}
					push (@{$track->{atomic}->{$cnt}}, $trig);
				}
			}

			# Add this group to the sort list.
			my @running = ();
			foreach my $i (sort { $b <=> $a } keys %{$track->{atomic}}) {
				push (@running,@{$track->{atomic}->{$i}});
			}
			foreach my $i (sort { $b <=> $a } keys %{$track->{option}}) {
				push (@running,@{$track->{option}->{$i}});
			}
			foreach my $i (sort { $b <=> $a } keys %{$track->{alpha}}) {
				push (@running,@{$track->{alpha}->{$i}});
			}
			foreach my $i (sort { $b <=> $a } keys %{$track->{number}}) {
				push (@running,@{$track->{number}->{$i}});
			}
			foreach my $i (sort { $b <=> $a } keys %{$track->{wild}}) {
				push (@running,@{$track->{wild}->{$i}});
			}
			push (@running,@{$track->{under}});
			push (@running,@{$track->{pound}});
			push (@running,@{$track->{star}});

			# Keep this buffer.
			$self->{sortedthat}->{$topic}->{$that} = [ @running ];
		}
	}
}

sub sortList {
	my ($self,$name,@list) = @_;

	# If a sorted list by this name already exists, delete it.
	if (exists $self->{sortlist}->{$name}) {
		delete $self->{sortlist}->{$name};
	}

	# Initialize the sorted list.
	$self->{sortlist}->{$name} = [];

	# Track by number of words.
	my $track = {};

	# Loop through each item in the list.
	foreach my $item (@list) {
		# Count the words.
		my @words = split(/\s+/, $item);
		my $cword = scalar(@words);

		# Store this by group of word counts.
		if (!exists $track->{$cword}) {
			$track->{$cword} = [];
		}
		push (@{$track->{$cword}}, $item);
	}

	# Sort them.
	my @sorted = ();
	foreach my $count (sort { $b <=> $a } keys %{$track}) {
		my @items = sort { length $b <=> length $a } @{$track->{$count}};
		push (@sorted,@items);
	}

	# Store this list.
	$self->{sortlist}->{$name} = [ @sorted ];
	return 1;
}

# Given one topic, walk the inheritence tree and return an array of all topics.
sub _getTopicTree {
	my ($self,$topic,$depth) = @_;

	# Break if we're in too deep.
	if ($depth > $self->{depth}) {
		$self->issue ("Deep recursion while scanning topic inheritance (topic $topic was involved)");
		return ();
	}

	# Collect an array of topics.
	my @topics = ($topic);

	$self->debug ("_getTopicTree depth $depth; topics: @topics");

	# Does this topic inherit others?
	if (exists $self->{lineage}->{$topic}) {
		# Try each of these.
		foreach my $inherits (sort { $a cmp $b } keys %{$self->{lineage}->{$topic}}) {
			$self->debug ("Topic $topic inherits $inherits");
			push (@topics, $self->_getTopicTree($inherits,($depth + 1)));
		}
		$self->debug ("_getTopicTree depth $depth (b); topics: @topics");
	}

	# Return them.
	return (@topics);
}

# Gather an array of all triggers in a topic. If the topic inherits other
# topics, recursively collect those triggers too. Take care about recursion.
sub _topicTriggers {
	my ($self,$topic,$triglvl,$depth) = @_;

	# Break if we're in too deep.
	if ($depth > $self->{depth}) {
		$self->issue ("Deep recursion while scanning topic inheritance (topic $topic was involved)");
		return ();
	}

	$self->debug ("Collecting trigger list for topic $topic");

	# topic:   the name of the topic
	# triglvl: either $self->{topics} or $self->{thats}
	# depth:   starts at 0 and ++'s with each recursion

	# Collect an array of triggers to return.
	my @triggers = ();

	# Does this topic inherit others?
	if (exists $self->{lineage}->{$topic}) {
		# Check every inherited topic.
		foreach my $inherits (sort { $a cmp $b } keys %{$self->{lineage}->{$topic}}) {
			$self->debug ("Topic $topic inherits $inherits");
			push (@triggers, $self->_topicTriggers($inherits,$triglvl,($depth + 1)));
		}
	}

	# Collect the triggers.
	push (@triggers, keys %{$triglvl->{$topic}});

	# Return them.
	return (@triggers);
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

sub getUservar {
	# Alias for getUservars.
	my $self = shift;
	return $self->getUservars (@_);
}

sub getUservars {
	my ($self,$user,$var) = @_;
	$user = '' unless defined $user;
	$var  = '' unless defined $var;

	# Did they want a specific variable?
	if (length $user && length $var) {
		if (exists $self->{client}->{$user}->{$var}) {
			return $self->{client}->{$user}->{$var};
		}
		else {
			return undef;
		}
	}

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

sub freezeUservars {
	my ($self,$user) = @_;
	$user = '' unless defined $user;

	if (length $user && exists $self->{client}->{$user}) {
		# Freeze their variables. First unfreeze the last copy if they
		# exist.
		if (exists $self->{frozen}->{$user}) {
			$self->thawUservars ($user, discard => 1);
		}

		# Back up all our variables.
		foreach my $var (keys %{$self->{client}->{$user}}) {
			next if $var eq "__history__";
			my $value = $self->{client}->{$user}->{$var};
			$self->{frozen}->{$user}->{$var} = $value;
		}

		# Back up the history.
		$self->{frozen}->{$user}->{__history__}->{input} = [
			@{$self->{client}->{$user}->{__history__}->{input}},
		];
		$self->{frozen}->{$user}->{__history__}->{reply} = [
			@{$self->{client}->{$user}->{__history__}->{reply}},
		];

		return 1;
	}

	return undef;
}

sub thawUservars {
	my ($self,$user,%args) = @_;
	$user = '' unless defined $user;

	if (length $user && exists $self->{frozen}->{$user}) {
		# What are we doing?
		my $restore = 1;
		my $discard = 1;
		if (exists $args{discard}) {
			# Just discard the variables.
			$restore = 0;
			$discard = 1;
		}
		elsif (exists $args{keep}) {
			# Keep the cache afterwards.
			$restore = 1;
			$discard = 0;
		}

		# Restore the state?
		if ($restore) {
			# Clear the client's current information.
			$self->clearUservars ($user);

			# Restore all our variables.
			foreach my $var (keys %{$self->{frozen}->{$user}}) {
				next if $var eq "__history__";
				my $value = $self->{frozen}->{$user}->{$var};
				$self->{client}->{$user}->{$var} = $value;
			}

			# Restore the history.
			$self->{client}->{$user}->{__history__}->{input} = [
				@{$self->{frozen}->{$user}->{__history__}->{input}},
			];
			$self->{client}->{$user}->{__history__}->{reply} = [
				@{$self->{frozen}->{$user}->{__history__}->{reply}},
			];
		}

		# Discard the cache?
		if ($discard) {
			foreach my $var (keys %{$self->{frozen}->{$user}}) {
				delete $self->{frozen}->{$user}->{$var};
			}
		}
		return 1;
	}

	return undef;
}

sub lastMatch {
	my ($self,$user) = @_;
	$user = '' unless defined $user;

	# Get this user's last matched trigger.
	if (length $user && exists $self->{client}->{$user}->{__lastmatch__}) {
		return $self->{client}->{$user}->{__lastmatch__};
	}

	return undef;
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

	# Avoid letting the user fall into a missing topic.
	if (!exists $self->{topics}->{$topic}) {
		$self->issue ("User $user was in an empty topic named '$topic'!");
		$topic = 'random';
		$self->{client}->{$user}->{topic} = 'random';
	}

	# Avoid deep recursion.
	if ($tags{step} > $self->{depth}) {
		my $ref = '';
		if (exists $self->{syntax}->{$topic}->{$msg}->{ref}) {
			$ref = " at $self->{syntax}->{$topic}->{$msg}->{ref}";
		}
		$self->issue ("ERR: Deep Recursion Detected$ref!");
		return "ERR: Deep Recursion Detected$ref!";
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
	my $matchedTrigger = undef;
	my $foundMatch = 0;

	# See if there are any %previous's in this topic, or any topic related to it.
	my @allTopics = ($topic);
	if (exists $self->{lineage}->{$topic}) {
		(@allTopics) = $self->_getTopicTree ($topic,0);
	}
	foreach my $top (@allTopics) {
		$self->debug ("Checking topic $top for any %previous's.");
		if (exists $self->{sortsthat}->{$top}) {
			$self->debug ("There's a %previous in this topic");

			# Do we have history yet?
			if (scalar @{$self->{client}->{$user}->{__history__}->{reply}} > 0) {
				my $lastReply = $self->{client}->{$user}->{__history__}->{reply}->[0];

				# Format the bot's last reply the same as the human's.
				$lastReply = $self->_formatMessage ($lastReply);

				$self->debug ("lastReply: $lastReply");

				# See if we find a match.
				foreach my $trig (@{$self->{sortsthat}->{$top}}) {
					my $botside = $self->_reply_regexp ($user,$trig);

					$self->debug ("Try to match lastReply ($lastReply) to $botside");

					# Look for a match.
					if ($lastReply =~ /^$botside$/i) {
						# Found a match! See if our message is correct too.
						(@thatstars) = ($lastReply =~ /^$botside$/i);
						foreach my $subtrig (@{$self->{sortedthat}->{$top}->{$trig}}) {
							my $humanside = $self->_reply_regexp ($user,$subtrig);

							$self->debug ("Now try to match $msg to $humanside");

							if ($msg =~ /^$humanside$/i) {
								$matched = $self->{thats}->{$top}->{$trig}->{$subtrig};
								$matchedTrigger = $top;
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
	}

	# Search their topic for a match to their trigger.
	if (not $foundMatch) {
		foreach my $trig (@{$self->{sorted}->{$topic}}) {
			# Process the triggers.
			my $regexp = $self->_reply_regexp ($user,$trig);

			$self->debug ("Trying to match \"$msg\" against $trig ($regexp)");

			if ($msg =~ /^$regexp$/i) {
				$self->debug ("Found a match!");

				# We found a match, but what if the trigger we matched belongs to
				# an inherited topic? Check for that.
				if (exists $self->{topics}->{$topic}->{$trig}) {
					# No, the trigger does belong to our own topic.
					$matched = $self->{topics}->{$topic}->{$trig};
				}
				else {
					# Our topic doesn't have this trigger. Check inheritence.
					$matched = $self->_findTriggerByInheritence ($topic,$trig,0);
				}

				$foundMatch = 1;
				$matchedTrigger = $trig;

				# Get the stars.
				(@stars) = ($msg =~ /^$regexp$/i);
				last;
			}
		}
	}

	# Store what trigger they matched on (if $matched is undef, this will be
	# too, which is great).
	$self->{client}->{$user}->{__lastmatch__} = $matchedTrigger;

	for (defined $matched) {
		# See if there are any hard redirects.
		if (exists $matched->{redirect}) {
			$self->debug ("Redirecting us to $matched->{redirect}");
			my $redirect = $matched->{redirect};
			$redirect = $self->processTags ($user,$msg,$redirect,[@stars],[@thatstars]);
			$self->debug ("Pretend user asked: $redirect");
			$reply = $self->_getreply ($user,$redirect,
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

				# Revert them to undefined values.
				$left = 'undefined' if $left eq '';
				$right = 'undefined' if $right eq '';

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

sub _findTriggerByInheritence {
	my ($self,$topic,$trig,$depth) = @_;

	# This sub was called because the user matched a trigger from the
	# sorted array, but the trigger doesn't exist under the topic of
	# which the user currently belongs. It probably was a trigger
	# inherited from another topic. This subroutine finds that out,
	# recursively, following the inheritence trail.

	# Take care to prevent infinite recursion.
	if ($depth > $self->{depth}) {
		$self->issue("Deep recursion detected while following an inheritence trail (involving topic $topic and trigger $trig)");
		return undef;
	}

	# See if this topic has an "inherits".
	if (exists $self->{lineage}->{$topic}) {
		foreach my $inherits (sort { $a cmp $b } keys %{$self->{lineage}->{$topic}}) {

			# See if this inherited topic has our trigger.
			if (exists $self->{topics}->{$inherits}->{$trig}) {
				# Great!
				return $self->{topics}->{$inherits}->{$trig};
			}
			else {
				# Check what this topic inherits from.
				my $match = $self->_findTriggerByInheritence (
					$inherits, $trig, ($depth + 1),
				);
				if (defined $match) {
					# Finally got a match.
					return $match;
				}
			}
		}
	}

	# Don't know what else we can do.
	return undef;
}

sub _reply_regexp {
	my ($self,$user,$regexp) = @_;

	# If the trigger is simply /^\*$/ (+ *) then the * there needs to
	# become (.*?) to match the blank string too.
	$regexp =~ s/^\*$/<zerowidthstar>/i;

	$regexp =~ s/\*/(.+?)/ig;        # Convert * into (.+?)
	$regexp =~ s/\#/(\\d+)/ig;    # Convert # into ([0-9]+?)
	$regexp =~ s/\_/(\\w+)/ig; # Convert _ into ([A-Za-z]+?)
	$regexp =~ s/\{weight=\d+\}//ig; # Remove {weight} tags.
	$regexp =~ s/<zerowidthstar>/(.*?)/i;
	while ($regexp =~ /\[(.+?)\]/i) { # Optionals
		my @parts = split(/\|/, $1);
		my @new = ();
		foreach my $p (@parts) {
			$p = '\s*' . $p . '\s*';
			push (@new,$p);
		}
		push (@new,'\s*');

		# If this optional had a star or anything in it, e.g. [*],
		# make that non-matching.
		my $pipes = join("|",@new);
		$pipes =~ s/\(\.\+\?\)/(?:.+?)/ig; # (.+?) --> (?:.+?)
		$pipes =~ s/\(\\d\+\)/(?:\\d+)/ig; # (\d+) --> (?:\d+)
		$pipes =~ s/\(\\w\+\)/(?:\\w+)/ig; # (\w+) --> (?:\w+)

		my $rep = "(?:$pipes)";
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

	# Filter in user variables.
	while ($regexp =~ /<get (.+?)>/i) {
		my $var = $1;
		my $rep = '';
		if (exists $self->{client}->{$user}->{$var}) {
			$rep = $self->{client}->{$user}->{$var};
			$rep =~ s/[^A-Za-z0-9 ]//ig;
			$rep = lc($rep);
		}
		$regexp =~ s/<get (.+?)>/$rep/i;
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
	$reply =~ s/<person>/{person}<star>{\/person}/ig;
	$reply =~ s/<\@>/{\@<star>}/ig;
	$reply =~ s/<formal>/{formal}<star>{\/formal}/ig;
	$reply =~ s/<sentence>/{sentence}<star>{\/sentence}/ig;
	$reply =~ s/<uppercase>/{uppercase}<star>{\/uppercase}/ig;
	$reply =~ s/<lowercase>/{lowercase}<star>{\/lowercase}/ig;

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
	foreach my $pattern (@{$self->{sortlist}->{subs}}) {
		my $result = $self->{subs}->{$pattern};
		$result =~ tr/A-Za-z/N-ZA-Mn-za-m/;
		my $qm = quotemeta($pattern);
		$string =~ s/^$qm$/<rot13sub>$result<bus31tor>/ig;
		$string =~ s/^$qm(\W+)/<rot13sub>$result<bus31tor>$1/ig;
		$string =~ s/(\W+)$qm(\W+)/$1<rot13sub>$result<bus31tor>$2/ig;
		$string =~ s/(\W+)$qm$/$1<rot13sub>$result<bus31tor>/ig;
	}
	while ($string =~ /<rot13sub>(.+?)<bus31tor>/i) {
		my $rot13 = $1;
		$rot13 =~ tr/A-Za-z/N-ZA-Mn-za-m/;
		$string =~ s/<rot13sub>(.+?)<bus31tor>/$rot13/i;
	}

	# Format punctuation.
	$string =~ s/[^A-Za-z0-9 ]//g;
	$string =~ s/^\s+//g;
	$string =~ s/\s+$//g;

	return $string;
}

sub _stringUtil {
	my ($self,$type,$string) = @_;

	if ($type eq 'formal') {
		$string =~ s/\b(\w+)\b/\L\u$1\E/ig;
	}
	elsif ($type eq 'sentence') {
		$string =~ s/\b(\w)(.*?)(\.|\?|\!|$)/\u$1\L$2$3\E/ig;
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

	# Substitute each of the sorted person sub arrays in order,
	# using a one-way substitution algorithm (read: base13).
	foreach my $pattern (@{$self->{sortlist}->{person}}) {
		my $result = $self->{person}->{$pattern};
		$result =~ tr/A-Za-z/N-ZA-Mn-za-m/;
		my $qm = quotemeta($pattern);
		$string =~ s/^$qm$/<rot13sub>$result<bus31tor>/ig;
		$string =~ s/^$qm(\W+)/<rot13sub>$result<bus31tor>$1/ig;
		$string =~ s/(\W+)$qm(\W+)/$1<rot13sub>$result<bus31tor>$2/ig;
		$string =~ s/(\W+)$qm$/$1<rot13sub>$result<bus31tor>/ig;
	}

	# Now rot13-decode what's left.
	while ($string =~ /<rot13sub>(.+?)<bus31tor>/i) {
		my $rot13 = $1;
		$rot13 =~ tr/A-Za-z/N-ZA-Mn-za-m/;
		$string =~ s/<rot13sub>(.+?)<bus31tor>/$rot13/i;
	}

	return $string;
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

  debug     - Turns on debug mode (a LOT of information will be printed to the
              terminal!). Default is 0 (disabled).
  verbose   - When debug mode is on, all debug output will be printed to the
              terminal if 'verbose' is also true. The default value is 1.
  debugfile - Optional: paired with debug mode, all debug output is also written
              to this file name. Since debug mode prints such a large amount of
              data, it is often more practical to have the output go to an
              external file for later review. Default is '' (no file).
  depth     - Determines the recursion depth limit when following a trail of replies
              that point to other replies. Default is 50.

It's recommended that if you set any other global variables that you do so by
calling C<setGlobal> or defining it within the RiveScript code. This will avoid
the possibility of overriding reserved globals. Currently, these variable names
are reserved:

  topics   sorted  sortsthat  sortedthat  thats
  arrays   subs    person     client      bot
  objects  syntax  sortlist   reserved    debugopts
  frozen

Note: the options "verbose" and "debugfile", when provided, are noted and then
deleted from the root object space, so that if your RiveScript code uses variables
by the same values it won't conflict with the values that you passed here.

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

=item getUservar ($USER, $VAR)

This is an alias for getUservars, and is here because it makes more grammatical
sense.

=item getUservars ([$USER][, $VAR])

Get all the variables about a user. If a username is provided, returns a hash
B<reference> containing that user's information. Else, a hash reference of all
the users and their information is returned.

You can optionally pass a second argument, C<$VAR>, to get a specific variable
that belongs to the user. For instance, C<getUservars ("soandso", "age")>.

This is like C<E<lt>getE<gt>> for a specific user or for all users.

=item clearUservars ([$USER])

Clears all variables about C<$USER>. If no C<$USER> is provided, clears all
variables about all users.

=item freezeUservars ($USER)

Freeze the current state of variables for user C<$USER>. This will back up the
user's current state (their variables and reply history). This won't statically
prevent the user's state from changing; it merely saves its current state. Then
use thawUservars() to revert back to this previous state.

=item thawUservars ($USER[, %OPTIONS])

If the variables for C<$USER> were previously frozen, this method will restore
them to the state they were in when they were last frozen. It will then delete
the stored cache by default. The following options are accepted as an additional
hash of parameters (these options are mutually exclusive and you shouldn't use
both of them at the same time. If you do, "discard" will win.):

  discard: Don't restore the user's state from the frozen copy, just delete the
           frozen copy.
  keep:    Keep the frozen copy even after restoring the user's state. With this
           you can repeatedly thawUservars on the same user to revert their state
           without having to keep freezing them again. On the next freeze, the
           last frozen state will be replaced with the new current state.

Examples:

  # Delete the frozen cache but don't modify the user's variables.
  $rs->thawUservars ("soandso", discard => 1);

  # Restore the user's state from cache, but don't delete the cache.
  $rs->thawUservars ("soandso", keep => 1);

=item lastMatch ($USER)

After fetching a reply for user C<$USER>, the C<lastMatch> method will return the
raw text of the trigger that the user has matched with their reply. This function
may return undef in the event that the user B<did not> match any trigger at all
(likely the last reply was "C<ERR: No Reply Matched>" as well).

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

=item sortThatTriggers *Internal

This method sorts all the C<+Trigger> lines that are paired with a common
C<%Previous> line. This is necessary for when one question by the bot could
have multiple replies. I found a bug with the following RS code:

  + how [are] you [doing]
  - I'm doing great, how are you?
  - Good -- how are you?
  - Fine, how are you?

  + [*] @good [*]
  % * how are you
  - That's good. :-)

  + [*] @bad [*]
  % * how are you
  - Aww. :-( What's the matter?

  + *
  % * how are you
  - I see...

The effective trigger order was "C<[*] @good [*]>", "C<*>", "C<[*] @bad [*]>",
because there was no sort buffer and it was relying on Perl's hash sorting.
This method was introduced to fix that problem and sort these triggers too.

You don't need to call this method yourself; it is called automatically
on a C<sortReplies()> request.

=item sortList ($NAME,@LIST) *Internal

This is used internally to sort arrays (namely, person and substitution pattern
arrays). Sets C<$rs->{sortlist}->{$NAME}> to an array reference of the sorted
values in C<@LIST>. The values are sorted by number of words from greatest to
smallest, with each group of same-word-count items sorted by length amongst
themselves.

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

  1.18  Dec 31 2008
  - Added support for topics to inherit their triggers from other topics.
    e.g. > topic alpha inherits beta
  - Fixed some bugs related to !array with ^continue's, and expanded its
    functionality therein.
  - Updated the getUservars() function to optionally be able to get just a specific
    variable from the user's data. Added getUservar() as a grammatically correct
    alias to this new functionality.
  - Added the functions freezeUservars() and thawUservars() to back up and
    restore a user's variables.
  - Added the function lastMatch(), which returns the text of the trigger that
    matched the user's last message.
  - The # command for RiveScript comments has been deprecated in revision 7 of
    the RiveScript Working Draft. The Perl module will now emit warnings each
    time the # comments are processed.
  - Modified a couple of triggers in the default Eliza brain to improve matching
    issues therein.
  - +Triggers can contain user <get> tags now.
  - Updated the RiveScript Working Draft.

  1.17  Sep 15 2008
  - Updated the rsdemo tool to be more flexible as a general debugging and
    developing program. Also updated rsdemo and rsup to include POD documentation
    that can be read via `perldoc`.
  - Added a global variable $RiveScript::basedir which is the the path to your
    Perl lib/RiveScript folder. This is used by `rsdemo` as its default location
    to search for replies.
  - Tweak: Triggers of only # and _ can exist now alongside the old single-wildcard
    trigger of *.
  - Bugfix: The lookahead code would throw Perl warnings if the following line
    had a single space in it, but was otherwise empty.
  - Bugfix: Inline comment removing has been fixed.
  - Bugfix: In conditionals, any blank side of the equality will get a default
    value of "undefined". This way you can use a matching array inside an optional
    and check if that <star> tag is defined.
    + i am wearing a [(@colors)] shirt
    * <star> ne undefined => Why are you wearing a <star> shirt?
    - What color is it?
  - Updated the RiveScript Working Draft.

  1.16  Jul 22 2008
  - New options to the constructor: 'verbose' and 'debugfile'. See the new()
    constructor for details.
  - Added new wildcard variants:
    * matches anything (previous behavior)
    # matches only numbers
    _ matches only letters
    So you can have a trigger like "+ i am # years old" and "+ i am * years old",
    with the latter trigger telling them to try that again and use a NUMBER this
    time. :)
  - Bugfix: when there were multiple +trigger's that had a common %previous,
    there was no internal sort buffer for those +trigger's. As a result, matching
    wasn't very efficient. Added the method sortThatTriggers() to fix this.
  - Bugfix: tags weren't being processed in @Redirects when they really
    should've!
  - Bugfix: The ^Continue lookahead code wouldn't work if the next line began
    with a tab. Fixed!
  - Updated the RiveScript Working Draft.

  1.15  Jun 19 2008
  - Person substitutions support multiple-word patterns now.
  - Message substititons also support multiple-word patterns now.
  - Added syntax tracking, so Deep Recursion errors can give you a filename and
    line number where the problem occurred.
  - Added a handler for detecting when a user was put into an empty topic.
  - Rearranged tag priority.
  - Updated the RiveScript Working Draft.

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
