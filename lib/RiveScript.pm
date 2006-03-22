package RiveScript;

use strict;
no strict 'refs';
use warnings;

our $VERSION = '0.14';

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto || 'RiveScript';

	my $self = {
		debug   => 0,
		reserved    => [      # Array of reserved (unmodifiable) keys.
			qw (reserved replies array syntax streamcache botvars uservars botarrays
			sort users substitutions library),
		],
		replies     => {},    # Replies
		array       => {},    # Sorted replies array
		syntax      => {},    # Keep files and line numbers
		streamcache => undef, # For streaming replies in
		botvars     => {},    # Bot variables (! var botname = Casey)
		substitutions => {},  # Substitutions (! sub don't = do not)
		person      => {},    # 1st/2nd person substitutions
		uservars    => {},    # User variables
		users       => {},    # Temporary things
		botarrays   => {},    # Bot arrays
		sort        => {},    # For reply sorting
		loops       => {},    # Reply recursion
		macros      => {},    # Subroutine macro objects
		library     => ['.'], # Include Libraries

		# Some editable globals.
		split_sentences    => 1,                    # Perform sentence-splitting.
		sentence_splitters => '! . ? ;',            # The sentence-splitters.
		macro_failure      => 'ERR(Macro Failure)', # Macro Failure Text
		@_,
	};

	# Set some environmental variables.
	$self->{botvars}->{ENV_OS}         = $^O;
	$self->{botvars}->{ENV_APPVERSION} = $VERSION;
	$self->{botvars}->{ENV_APPNAME}    = "RiveScript/$VERSION";

	# Input all Perl's env vars.
	foreach my $var (keys %ENV) {
		my $lab = 'ENV_SYS_' . $var;
		$self->{botvars}->{$lab} = $ENV{$var};
	}

	# Include Libraries.
	foreach my $inc (@INC) {
		push (@{$self->{library}}, "$inc/RiveScript/RSLIB");
	}

	bless ($self,$class);
	return $self;
}

sub debug {
	my ($self,$msg) = @_;

	print "RiveScript // $msg\n" if $self->{debug} == 1;
}

sub setSubroutine {
	my ($self,%subs) = @_;

	foreach my $sub (keys %subs) {
		$self->{macros}->{$sub} = $subs{$sub};
	}
}

sub setGlobal {
	my ($self,%data) = @_;

	foreach my $key (keys %data) {
		my $lc = lc($key);
		$lc =~ s/ //g;

		my $ok = 1;
		foreach my $res (@{$self->{reserved}}) {
			if ($res eq $lc) {
				warn "Can't modify reserved global $res";
				$ok = 0;
			}
		}

		next unless $ok;

		# Delete global?
		if ($data{$key} eq 'undef') {
			delete $self->{$key};
		}
		else {
			$self->{$key} = $data{$key};
		}
	}
}

sub setVariable {
	my ($self,%data) = @_;

	foreach my $key (keys %data) {
		if ($data{$key} eq 'undef') {
			delete $self->{botvars}->{$key};
		}
		else {
			$self->{botvars}->{$key} = $data{$key};
		}
	}
}

sub setSubstitution {
	my ($self,%data) = @_;

	foreach my $key (keys %data) {
		if ($data{$key} eq 'undef') {
			delete $self->{substitutions}->{$key};
		}
		else {
			$self->{substitutions}->{$key} = $data{$key};
		}
	}
}

sub setArray {
	my ($self,%data) = @_;

	foreach my $key (keys %data) {
		if ($data{$key} eq 'undef') {
			delete $self->{botarrays}->{$key};
		}
		else {
			$self->{botarrays}->{$key} = $data{$key};
		}
	}
}

sub setUservar {
	my ($self,$user,%data) = @_;

	foreach my $key (keys %data) {
		if ($data{$key} eq 'undef') {
			delete $self->{uservars}->{$user}->{$key};
		}
		else {
			$self->{uservars}->{$user}->{$key} = $data{$key};
		}
	}
}

sub getUservars {
	my $self = shift;
	my $user = shift || '__rivescript__';

	# Return uservars for a specific user?
	if ($user ne '__rivescript__') {
		return $self->{uservars}->{$user};
	}
	else {
		my $returned = {};

		foreach my $user (keys %{$self->{uservars}}) {
			foreach my $var (keys %{$self->{uservars}->{$user}}) {
				$returned->{$user}->{$var} = $self->{uservars}->{$user}->{$var};
			}
		}

		return $returned;
	}
}

sub loadDirectory {
	my $self = shift;
	my $dir = shift;
	my @ext = ('.rs');
	if (scalar(@_)) {
		@ext = @_;
	}

	# Load a directory.
	if (-d $dir) {
		# Include "begin.rs" first.
		if (-e "$dir/begin.rs") {
			print "Loading begin.rs first!\n";
			$self->loadFile ("$dir/begin.rs");
		}

		opendir (DIR, $dir);
		foreach my $file (sort(grep(!/^\./, readdir(DIR)))) {
			next if $file eq 'begin.rs';

			# Load in this file.
			my $okay = 0;
			foreach my $type (@ext) {
				if ($file =~ /$type$/i) {
					$okay = 1;
					last;
				}
			}

			$self->loadFile ("$dir/$file") if $okay;
		}
		closedir (DIR);
	}
	else {
		warn "RiveScript // The directory $dir doesn't exist!";
	}
}

sub stream {
	my ($self,$code) = @_;

	$self->{streamcache} = $code;
	$self->loadFile (undef,1);
}

sub loadFile {
	my $self = shift;
	my $file = shift || '(Streamed)';
	my $stream = shift || 0;

	# Prepare to load the file.
	my @data = ();

	# Streaming in replies?
	if ($stream) {
		@data = split(/\n/, $self->{streamcache});
		chomp @data;
	}
	else {
		open (FILE, $file);
		@data = <FILE>;
		close (FILE);
		chomp @data;
	}

	$self->debug ("Parsing in file $file");

	# Set up parser variables.
	my $started = 0;        # Haven't found a trigger yet
	my $inReply = 0;        # Not in a reply yet
	my $inCom   = 0;        # Not in commented code
	my $inObj   = 0;        # In an object.
	my $objName = '';       # Object's name
	my $objCode = '';       # Object's source.
	my $topic   = 'random'; # Default topic
	my $trigger = '';       # The trigger we're on
	my $replies = 0;        # -REPLY counter
	my $conds   = 0;        # *CONDITION counter
	my $num     = 0;        # Line numbers.
	my $conc    = 0;        # Concetanate the last command (0.06)
	my $lastCmd = '';       # The last command used (0.06)

	# Go through the file.
	foreach my $line (@data) {
		$num++;

		# If in an object...
		if ($inObj == 1) {
			if ($line !~ /< object/i) {
				$objCode .= "$line\n";
				next;
			}
		}

		# Format the line.
		$self->debug ("Line $num ($inCom): $line");
		next if length $line == 0; # Skip blank lines
		$line =~ s/^[\s\t]*//ig;     # Remove prepent whitepaces
		$line =~ s/[\s\t]*$//ig;     # Remove appent whitespaces

		if ($line =~ /^\s/) {
			print "Line: $line\n";
		}

		# Separate the command from its data.
		my ($command,$data) = split(/\s+/, $line, 2);

		# Filter in hard spaces.
		$data =~ s/\\s/ /g if defined $data;

		# Check for comment commands...
		if ($command =~ /^\/\//) {
			# Single comment. Skip it.
			next;
		}
		if ($command eq '/*') {
			# We're starting a comment section.
			if (defined $data && $data =~ /\*\//) {
				# The section was ended here too.
				next;
			}
			$inCom = 1;
		}
		if ($command eq '*/' || (defined $data && $data =~ /\*\//)) {
			$inCom = 0;
			next;
		}

		# Skip comments.
		next if $inCom;

		next unless length $command;

		# Concatenate previous commands.
		if ($command eq '^') {
			$self->debug ("^ Command - Command Continuation");

			if ($lastCmd =~ /^\! global (.*?)$/i) {
				my $var = $1;
				$self->{$var} .= $data;
			}
			elsif ($lastCmd =~ /^\! var (.*?)$/i) {
				my $var = $1;
				$self->{botvars}->{$var} .= $data;
			}
			elsif ($lastCmd =~ /^\! array (.*?)$/i) {
				my $var = $1;
				if ($data =~ /\|/) {
					my @words = split(/\|/, $data);
					push (@{$self->{botarrays}->{$var}}, @words);
				}
				else {
					my @words = split(/\s+/, $data);
					push (@{$self->{botarrays}->{$var}}, @words);
				}
			}
			elsif ($lastCmd =~ /^\+ (.*?)$/i) {
				my $tr = $1;
				$trigger = $tr . $data;
			}
			elsif ($lastCmd =~ /^\% (.*?)$/i) {
				my $that = $1;
				$topic .= $data;
			}
			elsif ($lastCmd =~ /^\@ (.*?)$/i) {
				my $at = $1;
				$self->{replies}->{$topic}->{$trigger}->{redirect} .= $data;
			}
			else {
				# Normal behavior
				$self->{replies}->{$topic}->{$trigger}->{$replies} .= $data;
			}

			next;
		}

		# Go through actual commands.
		if ($command eq '>') {
			$self->debug ("> Command - Label Begin!");
			my ($type,$text) = split(/\s+/, $data, 2);
			if ($type eq 'topic') {
				$self->debug ("\tTopic set to $text");
				$topic = $text;
			}
			elsif ($type eq 'begin') {
				$self->debug ("\tA begin handler");
				$topic = '__begin__';
			}
			elsif ($type eq 'object') {
				$self->debug ("\tAn object");
				$objName = $text || 'unknown';
				$inObj = 1;
			}
			else {
				warn "Unknown label type at $file line $num";
			}
		}
		elsif ($command eq '<') {
			$self->debug ("< Command - Label End!");
			if ($data eq 'topic' || $data eq '/topic' || $data eq 'begin' || $data eq '/begin') {
				$self->debug ("\tTopic reset!");
				$topic = 'random';
			}
			elsif ($data eq 'object') {
				# Save the object.
				my $code = "\$self->setSubroutine ($objName => \\&rscode_$objName);\n\n"
					. "sub rscode_$objName {\n"
					. "$objCode\n"
					. "}\n";

				my $eval = eval $code;
				$inObj = 0;
				$objName = '';
				$objCode = '';
			}
			else {
				warn "Unknown label ender at $file line $num";
			}
		}
		elsif ($command eq '!') {
			$self->debug ("! Command - Definition");

			my ($type,$details) = split(/\s+/, $data, 2);
			my ($what,$is) = split(/=/, $details, 2);
			$what =~ s/\s//g if defined $what;
			$is =~ s/^\s//g if defined $is;
			$type =~ s/\s//g;
			$type = lc($type);

			# Globals?
			if ($type eq 'global') {
				my $err = 0;
				foreach my $reserved (@{$self->{reserved}}) {
					if ($what eq $reserved) {
						$err = 1;
						last;
					}
				}

				# Skip if there was a problem.
				if ($err) {
					warn "Can't modify reserved global $what";
					next;
				}

				$lastCmd = "! global $what";

				# Set this top-level global.
				if ($is ne 'undef') {
					$self->debug ("\tSet global $what = $is");
					$self->{$what} = $is;
				}
				else {
					$self->debug ("\tDeleting global $what");
					delete $self->{$what};
				}
			}
			elsif ($type eq 'var') {
				# Can't overwrite reserved variables.
				my $err = undef;
				if ($what =~ /^env_/i) {
					$err = "Can't modify an environmental variable!";
				}

				if ($err) {
					warn "$err";
					next;
				}

				# Set a botvariable.
				$lastCmd = "! var $what";
				if ($is ne 'undef') {
					$self->debug ("\tSet botvar $what = $is");
					$self->{botvars}->{$what} = $is;
				}
				else {
					$self->debug ("\tDeleting botvar $what");
					delete $self->{botvars}->{$what};
				}
			}
			elsif ($type eq 'array') {
				# An array.
				$lastCmd = "! array $what";

				# Delete the array?
				if ($is eq 'undef') {
					$self->debug ("\tDeleting array $what");
					delete $self->{botarrays}->{$what};
					next;
				}

				$self->debug ("\tSetting array $what = $is");
				my @array = ();

				# Does it contain pipes?
				if ($is =~ /\|/) {
					# Split at them.
					@array = split(/\|/, $is);
				}
				else {
					# Split at spaces.
					@array = split(/\s+/, $is);
				}

				# Keep them.
				$self->{botarrays}->{$what} = [ @array ];
			}
			elsif ($type eq 'sub') {
				# Substitutions.

				if ($is ne 'undef') {
					$self->debug ("\tSet substitution $what = $is");
					$self->{substitutions}->{$what} = $is;
				}
				else {
					$self->debug ("\tDeleting substitution $what");
					delete $self->{substitutions}->{$what};
				}
			}
			elsif ($type eq 'person') {
				# Person substitutions.

				if ($is ne 'undef') {
					$self->debug ("\tSet person $what = $is");
					$self->{person}->{$what} = $is;
				}
				else {
					$self->debug ("\tDeleting person $what");
					delete $self->{person}->{$what};
				}
			}
			elsif ($type eq 'addpath') {
				# Add a search path.
				if (defined $what) {
					push (@{$self->{library}}, $what);
				}
			}
			elsif ($type eq 'include') {
				# An Include Directive

				my $found = 0;
				my $path = '';
				foreach my $inc (@{$self->{library}}) {
					if (-e "$inc/$what") {
						$found = 1;
						$path = "$inc/$what";
						last;
					}
				}

				$self->loadFile ("$path");
			}
			else {
				warn "Unsupported type at $file line $num";
			}
		}
		elsif ($command eq '+') {
			$self->debug ("+ Command - Reply Trigger!");

			if ($inReply == 1) {
				# Reset the topics?
				if ($topic =~ /^__that__/i) {
					$topic = 'random';
				}

				# New reply.
				$inReply = 0;
				$trigger = '';
				$replies = 0;
				$conds = 0;
			}

			# Reply trigger.
			$inReply = 1;
			$trigger = $data;
			$lastCmd = "+ $trigger";
			$self->debug ("\tTrigger: $trigger");

			# Set the trigger under its topic.
			$self->{replies}->{$topic}->{$trigger}->{topic} = $topic;
			$self->{syntax}->{$topic}->{$trigger}->{ref} = "$file line $num";
		}
		elsif ($command eq '%') {
			$self->debug ("% Command - Previous!");

			if ($inReply != 1) {
				# Error.
				warn "Syntax error at $file line $num";
				next;
			}

			# Set the topic to "__that__$data"
			$lastCmd = "\% $data";
			$topic = "__that__$data";
		}
		elsif ($command eq '-') {
			$self->debug ("- Command - Response!");

			$lastCmd = ''; # -Reply is the default usage for ^Continue

			if ($inReply != 1) {
				# Error.
				warn "Syntax error at $file line $num";
				next;
			}

			# Reply response.
			$replies++;

			$self->{replies}->{$topic}->{$trigger}->{$replies} = $data;
			$self->{syntax}->{$topic}->{$trigger}->{$replies}->{ref} = "$file line $num";
		}
		elsif ($command eq '@') {
			$self->debug ("\@ Command - Redirect");

			if ($inReply != 1) {
				# Error.
				warn "Syntax error at $file line $num";
				next;
			}

			$lastCmd = "\@ $data";

			$self->{replies}->{$topic}->{$trigger}->{redirect} = $data;
			$self->{syntax}->{$topic}->{$trigger}->{redirect}->{ref} = "$file line $num";
		}
		elsif ($command eq '*') {
			$self->debug ("* Command - Conditional");

			if ($inReply != 1) {
				# Error.
				warn "Syntax error at $file line $num";
				next;
			}

			$conds++;
			$self->{replies}->{$topic}->{$trigger}->{conditions}->{$conds} = $data;
			$self->{syntax}->{$topic}->{$trigger}->{conditions}->{$conds}->{ref} = "$file line $num";
		}
		elsif ($command eq '&') {
			$self->debug ("\& Command - Perl Code");

			if ($inReply != 1) {
				# Error.
				warn "Syntax error at $file line $num";
				next;
			}

			$self->{replies}->{$topic}->{$trigger}->{system}->{codes} .= $data;
			$self->{syntax}->{$topic}->{$trigger}->{system}->{codes}->{ref} = "$file line $num";
		}
		else {
			warn "Unknown command $command at $file line $num;";
		}
	}
}

sub sortReplies {
	my ($self) = @_;

	# Reset defaults.
	$self->{sort}->{replycount} = 0;

	# Fail if replies hadn't been loaded.
	return 0 unless (scalar (keys %{$self->{replies}}));

	# Delete the replies array if it exists.
	if (exists $self->{array}) {
		delete $self->{array};
	}

	$self->debug ("Sorting the replies...");

	# Count them while we're at it.
	my $count = 0;

	# Go through each reply.
	foreach my $topic (keys %{$self->{replies}}) {
		# print "Sorting replies under topic $topic...\n";

		# Sort by number of whole words (or, not wildcards).
		my $sort = {
			def => [],
			unknown => [],
		};
		for (my $i = 0; $i <= 50; $i++) {
			$sort->{$i} = [];
		}

		# Set trigger arrays.
		my @trigNorm = ();
		my @trigWild = ();

		# Go through each item.
		foreach my $key (keys %{$self->{replies}->{$topic}}) {
			$count++;

			# print "\tSorting $key\n";

			# If this has wildcards...
			if ($key =~ /\*/) {
				# See how many full words it has.
				my @words = split(/\s/, $key);
				my $cnt = 0;
				foreach my $word (@words) {
					$word =~ s/\s//g;
					next unless length $word;
					if ($word !~ /\*/) {
						# A whole word.
						$cnt++;
					}
				}

				# What did we get?
				$cnt = 50 if $cnt > 50;

				# print "\t\tWildcard with $cnt words\n";

				if (exists $sort->{$cnt}) {
					push (@{$sort->{$cnt}}, $key);
				}
				else {
					push (@{$sort->{unknown}}, $key);
				}
			}
			else {
				# Save to normal array.
				# print "\t\tNormal trigger\n";
				push (@{$sort->{def}}, $key);
			}
		}

		# Merge all the arrays.
		$self->{array}->{$topic} = [
			@{$sort->{def}},
		];
		for (my $i = 50; $i >= 1; $i--) {
			push (@{$self->{array}->{$topic}}, @{$sort->{$i}});
		}
		push (@{$self->{array}->{$topic}}, @{$sort->{unknown}});
		push (@{$self->{array}->{$topic}}, @{$sort->{0}});
	}

	# Save the count.
	$self->{sort}->{replycount} = $count;
	return 1;
}

sub reply {
	my $self = shift;
	my $id = shift;
	my $msg = shift;

	my %args = (
		scalar   => 0, # Force scalar return
		no_split => 0, # No sentence-splitting
		retry    => 0, # DO NOT RECONFIGURE THIS
		@_,
	);

	# Reset loops.
	$self->{loops} = 0;

	# print "reply called\n";

	# Send this through the "BEGIN" reply first.
	my $begin = '{ok}';
	if (exists $self->{replies}->{__begin__}->{request}) {
		my $userTopic = $self->{users}->{$id}->{topic} || 'random';
		$self->{users}->{$id}->{topic} = '__begin__';
		$begin = $self->intReply ($id,'request', tags => 0);
		$self->{users}->{$id}->{topic} = $userTopic;

		# Prerun any topic tags present.
		if ($begin =~ /\{topic=(.*?)\}/i) {
			my $to = $1;
			$self->{users}->{$id}->{topic} = $to;
			$begin =~ s/\{topic=(.*?)\}//g;
		}
	}

	my @out = ();
	if ($begin =~ /\{ok\}/i) {
		# Format their message.
		unless ($args{no_split}) {
			my @sentences = $self->splitSentences ($msg);
			foreach my $in (@sentences) {
				$in = $self->formatMessage ($in);
				next unless length $in > 0;
				# print "Sending sentence \"$in\" in...\n";
				my @returned = $self->intReply ($id,$in);
				push (@out,@returned);
			}
		}
		else {
			$msg = $self->formatMessage ($msg);
			my @returned = $self->intReply ($id,$msg);
			push (@out,@returned);
		}

		my @final = ();

		my $reply = $begin;
		foreach (@out) {
			$reply =~ s/\{ok\}/$_/ig;
			$reply = $self->tagFilter ($reply,$id,$msg);
			push (@final,$reply);
		}

		# Get it in scalar form.
		my $scalar = join (" ", @final);

		# Run final filters on it (for begin statement's sake).
		# $scalar = $self->tagFilter ($scalar,$id,$msg);

		# If no reply, try again without sentence-splitting.
		if (($scalar =~ /^ERR: No Reply/ || length $scalar == 0) && $args{retry} != 1) {
			my @array = $self->reply ($id,$msg, no_split => 1, retry => 1, scalar => 0);
			(@final) = (@array);
		}

		# Return in scalar form?
		if ($args{scalar}) {
			return join (" ", @final);
		}

		return @final;
	}
	else {
		# Run tag filters anyway.
		my $userTopic = $self->{users}->{$id}->{topic} || 'random';
		$self->{users}->{$id}->{topic} = '__begin__';
		$begin = $self->tagFilter ($begin,$id,$msg);
		$self->{users}->{$id}->{topic} = $userTopic;
		return $begin;
	}
}

sub intReply {
	my ($self,$id,$msg,%inArgs) = @_;
	$inArgs{tags} = 1 unless exists $inArgs{tags};

	# Sort replies if they haven't been yet.
	if (!(scalar(keys %{$self->{array}}))) {
		warn "You should sort replies BEFORE calling reply()!";
		$self->sortReplies;
	}

	# Create this user's history.
	if (!exists $self->{users}->{$id}->{history}) {
		$self->{users}->{$id}->{history}->{input} = ['', 'undefined', 'undefined', 'undefined', 'undefined',
			'undefined', 'undefined', 'undefined', 'undefined', 'undefined' ];
		$self->{users}->{$id}->{history}->{reply} = ['', 'undefined', 'undefined', 'undefined', 'undefined',
			'undefined', 'undefined', 'undefined', 'undefined', 'undefined' ];
		# print "\tCreated user history\n";
	}

	# Too many loops?
	if ($self->{loops} >= 15) {
		$self->{loops} = 0;
		my $topic = $self->{users}->{$id}->{topic} || 'random';
		return "ERR: Deep Recursion (15+ loops in reply set) at $self->{syntax}->{$topic}->{$msg}->{redirect}->{ref}";
	}

	# Create variables.
	my @stars = (); # Wildcard captors
	my $reply; # The final reply.

	# Topics?
	$self->{users}->{$id}->{topic} ||= 'random';

	# Setup the user's temporary history.
	$self->{users}->{$id}->{last} = '' unless exists $self->{users}->{$id}->{last}; # Last Msg
	$self->{users}->{$id}->{that} = '' unless exists $self->{users}->{$id}->{that}; # Bot Last Reply

	# Make sure some replies are loaded.
	if (!exists $self->{replies}) {
		return "ERR: No replies have been loaded!";
	}

	# See if this topic has any "that's" associated with it.
	my $thatTopic = "__that__$self->{users}->{$id}->{that}";
	my $lastSent = $self->{users}->{$id}->{that};
	my $isThat = 0;
	my $keepTopic = '';

	# Go through each reply.
	# print "Scanning through topics...\n";
	foreach my $topic (keys %{$self->{array}}) {
		# print "\tOn Topic: $topic\n";
		if ($isThat != 1 && length $lastSent > 0 && exists $self->{replies}->{$thatTopic}->{$msg}) {
			# It does exist. Set this as the topic so this reply should be matched.
			$isThat = 1;
			$keepTopic = $self->{users}->{$id}->{topic};
			$self->{users}->{$id}->{topic} = $thatTopic;
		}

		# Don't look at topics that aren't ours.
		next unless $topic eq $self->{users}->{$id}->{topic};

		# print "\tThis is our topic!\n";

		# Check the inputs.
		foreach my $in (@{$self->{array}->{$topic}}) {
			last if defined $reply;
			# Slightly format the trigger to be regexp friendly.
			my $regexp = $in;
			$regexp =~ s~\*~(.*?)~g;

			# Run optional modifiers.
			while ($regexp =~ /\[(.*?)\]/i) {
				my $o = $1;
				my @parts = split(/\|/, $o);
				my @new = ();

				foreach my $word (@parts) {
					$word = '\s*' . $word . '\s*';
					push (@new,$word);
				}

				push (@new,'\s*');
				my $rep = '(' . join ('|',@new) . ')';

				$regexp =~ s/\s*\[(.*?)\]\s*/$rep/i;
			}

			# Filter in arrays.
			while ($regexp =~ /\@(.+?)\b/i) {
				my $o = $1;
				my $name = $o;
				my $rep = '';
				if (exists $self->{botarrays}->{$name}) {
					$rep = '(?:' . join ('|', @{$self->{botarrays}->{$name}}) . ')';
				}
				$regexp =~ s/\@$o\b/$rep/ig;
			}

			# Filter in botvariables.
			while ($regexp =~ /<bot (.*?)>/i) {
				my $o = $1;
				my $value = $self->{botvars}->{$o};
				$value =~ s/[^A-Za-z0-9 ]//g;
				$value = lc($value);
				$regexp =~ s/<bot (.*?)>/$value/i;
			}

			# print "\tComparing $msg with $regexp\n";

			# See if it's a match.
			if ($msg =~ /^$regexp$/i) {
				# Collect the stars.
				@stars = $msg =~ /^$regexp$/i;
				unshift (@stars, ''); # Make $stars[1] equal <star1>

				# A solid redirect? (@ command)
				if (exists $self->{replies}->{$topic}->{$in}->{redirect}) {
					my $redirect = $self->{replies}->{$topic}->{$in}->{redirect};

					# Filter wildcards into it.
					$redirect = $self->mergeWildcards ($redirect,\@stars);

					# Plus a loop.
					$self->{loops}++;
					$reply = $self->intReply ($id,$redirect);
					return $reply;
				}

				# Check for conditionals.
				if (exists $self->{replies}->{$topic}->{$in}->{conditions}) {
					for (my $c = 1; exists $self->{replies}->{$topic}->{$in}->{conditions}->{$c}; $c++) {
						last if defined $reply;

						my $condition = $self->{replies}->{$topic}->{$in}->{conditions}->{$c};
						my ($cond,$happens) = split(/=>/, $condition, 2);
						$cond =~ s/\s$//g;
						$happens =~ s/^\s//g;

						# Find out what type of condition this is.
						if ($cond =~ /^(.*?)(=|!=|<=|>=|<|>|\?)(.*?)$/i) {
							my ($var,$type,$value) = ($1,$2,$3);

							$var =~ s/\s+$//g; $var =~ s/^\s+//g;
							$value =~ s/\s+$//g; $value =~ s/^\s+//g;

							# If this is specifically a botvariable...
							my $isBotVar = 0;
							my $checkUser = 1;
							if ($var =~ /^\#/) {
								$isBotVar = 1;
								$var =~ s/^\#//g;
							}

							# Get candidates for value matches.
							my $botVar = $self->{botvars}->{$var};
							my $usrVar = $self->{uservars}->{$id}->{$var};

							if (defined $botVar || defined $usrVar) {

								# Our check types:
								# =  equal to
								# != not equal
								# <  less than
								# <= less than or equal to
								# >  greater than
								# >= greater than or equal to
								# ?  defined

								if ($type eq '?') {
									if (defined $usrVar) {
										$reply = $happens;
									}
								}
								elsif ($type eq '=') {
									if (defined $botVar || defined $usrVar) {
										if (defined $botVar && $botVar eq $value) {
											$reply = $happens;
											$checkUser = 0;
										}

										if ($checkUser && !$isBotVar && defined $usrVar && $usrVar eq $value) {
											$reply = $happens;
										}
									}
								}
								elsif ($type eq '!=') {
									if (defined $botVar || defined $usrVar) {
										if (defined $botVar && $botVar ne $value) {
											$reply = $happens;
											$checkUser = 0;
										}

										if ($checkUser && !$isBotVar && defined $usrVar && $usrVar ne $value) {
											$reply = $happens;
										}
									}
								}
								elsif ($type eq '<') {
									if (defined $botVar || defined $usrVar) {
										if (defined $botVar && $botVar !~ /[^0-9]/ && $botVar < $value) {
											$reply = $happens;
											$checkUser = 0;
										}

										if ($checkUser && !$isBotVar && defined $usrVar && $usrVar !~ /[^0-9]/ && $usrVar < $value) {
											$reply = $happens;
										}
									}
								}
								elsif ($type eq '<=') {
									if (defined $botVar || defined $usrVar) {
										if (defined $botVar && $botVar !~ /[^0-9]/ && $botVar <= $value) {
											$reply = $happens;
											$checkUser = 0;
										}

										if ($checkUser && !$isBotVar && defined $usrVar && $usrVar !~ /[^0-9]/ && $usrVar <= $value) {
											$reply = $happens;
										}
									}
								}
								elsif ($type eq '>') {
									if (defined $botVar || defined $usrVar) {
										if (defined $botVar && $botVar !~ /[^0-9]/ && $botVar > $value) {
											$reply = $happens;
											$checkUser = 0;
										}

										if ($checkUser && !$isBotVar && defined $usrVar && $usrVar !~ /[^0-9]/ && $usrVar > $value) {
											$reply = $happens;
										}
									}
								}
								elsif ($type eq '>=') {
									if (defined $botVar || defined $usrVar) {
										if (defined $botVar && $botVar !~ /[^0-9]/ && $botVar >= $value) {
											$reply = $happens;
											$checkUser = 0;
										}

										if ($checkUser && !$isBotVar && defined $usrVar && $usrVar !~ /[^0-9]/ && $usrVar >= $value) {
											$reply = $happens;
										}
									}
								}
							}
						}
					}
				}

				# If we have a reply, quit.
				last if defined $reply;

				# Get a random reply now.
				my @random = ();
				my $totweight = 0;
				for (my $i = 1; exists $self->{replies}->{$topic}->{$in}->{$i}; $i++) {
					my $item = $self->{replies}->{$topic}->{$in}->{$i};
					if ($item =~ /\{weight=(.*?)\}/i) {
						my $weight = $1;
						$item =~ s/\{weight=(.*?)\}//g;
						if ($weight !~ /[^0-9]/i) {
							$totweight += $weight;

							for (my $i = $weight; $i >= 0; $i--) {
								push (@random,$item);
							}
						}
						next;
					}
					push (@random, $self->{replies}->{$topic}->{$in}->{$i});
				}

				# print "\@random = " . scalar(@random) . "\n";
				$reply = $random [ int(rand(scalar(@random))) ];

				# Run system commands.
				if (exists $self->{replies}->{$topic}->{$in}->{system}->{codes}) {
					my $eval = eval ($self->{replies}->{$topic}->{$in}->{system}->{codes});
				}
			}
		}
	}

	# Reset "that" topics.
	if ($isThat == 1) {
		$self->{users}->{$id}->{topic} = $keepTopic;
		$self->{users}->{$id}->{that} = '<<undef>>';
	}

	# A reply?
	if (defined $reply) {
		# Filter in stars...
		$reply = $self->mergeWildcards ($reply,\@stars);
	}
	else {
		# Were they in a possibly broken topic?
		if ($self->{users}->{$id}->{topic} ne 'random') {
			if (exists $self->{array}->{$self->{users}->{$id}->{topic}}) {
				$reply = "ERR: No Reply Matched in Topic $self->{users}->{$id}->{topic}";
			}
			else {
				$self->{users}->{$id}->{topic} = 'random'; # Breakaway
				$reply = "ERR: No Reply in Topic $self->{users}->{$id}->{topic} (possibly void topic?)";
			}
		}
		else {
			$reply = "ERR: No Reply Found";
		}
	}

	# Filter tags in.
	$reply = $self->tagFilter ($reply,$id,$msg) if $inArgs{tags};

	# Update history.
	shift (@{$self->{users}->{$id}->{history}->{input}});
	shift (@{$self->{users}->{$id}->{history}->{reply}});
	unshift (@{$self->{users}->{$id}->{history}->{input}}, $msg);
	unshift (@{$self->{users}->{$id}->{history}->{reply}}, $reply);
	unshift (@{$self->{users}->{$id}->{history}->{input}}, '');
	unshift (@{$self->{users}->{$id}->{history}->{reply}}, '');
	pop (@{$self->{users}->{$id}->{history}->{input}});
	pop (@{$self->{users}->{$id}->{history}->{reply}});

	# Format the bot's reply.
	my $simple = lc($reply);
	$simple =~ s/[^A-Za-z0-9 ]//g;
	$simple =~ s/^\s+//g;
	$simple =~ s/\s$//g;

	# Save this message.
	$self->{users}->{$id}->{that} = $simple;
	$self->{users}->{$id}->{last} = $msg;
	$self->{users}->{$id}->{hold} ||= 0;

	# Reset the loop timer.
	$self->{loops} = 0;

	# There SHOULD be a reply now.
	# Return it in pairs at {nextreply}
	if ($reply =~ /\{nextreply\}/i) {
		my @returned = split(/\{nextreply\}/i, $reply);
		return @returned;
	}

	# Filter in line breaks.
	$reply =~ s/\\n/\n/g;

	return $reply;
}

sub search {
	my ($self,$string) = @_;

	# Search for this string.
	$string = $self->formatMessage ($string);

	my @result = ();
	foreach my $topic (keys %{$self->{array}}) {
		foreach my $trigger (@{$self->{array}->{$topic}}) {
			my $regexp = $trigger;
			$regexp =~ s~\*~\(\.\*\?\)~g;

			# Run optional modifiers.
			while ($regexp =~ /\[(.*?)\]/i) {
				my $o = $1;
				my @parts = split(/\|/, $o);
				my @new = ();

				foreach my $word (@parts) {
					$word = ' ' . $word . ' ';
					push (@new,$word);
				}

				push (@new,' ');
				my $rep = '(' . join ('|',@new) . ')';

				$regexp =~ s/\s*\[(.*?)\]\s*/$rep/g;
			}

			# Filter in arrays.
			while ($regexp =~ /\(\@(.*?)\)/i) {
				my $o = $1;
				my $name = $o;
				my $rep = '';
				if (exists $self->{botarrays}->{$name}) {
					$rep = '(' . join ('|', @{$self->{botarrays}->{$name}}) . ')';
				}
				$regexp =~ s/\(\@$o\)/$rep/ig;
			}

			# Filter in botvariables.
			while ($regexp =~ /<bot (.*?)>/i) {
				my $o = $1;
				my $value = $self->{botvars}->{$o};
				$value =~ s/[^A-Za-z0-9 ]//g;
				$value = lc($value);
				$regexp =~ s/<bot $o>/$value/ig;
			}

			# Match?
			if ($string =~ /^$regexp$/i) {
				push (@result, "$trigger (topic: $topic) at $self->{syntax}->{$topic}->{$trigger}->{ref}");
			}
		}
	}

	return @result;
}

sub splitSentences {
	my ($self,$msg) = @_;

	# Split at sentence-splitters?
	if ($self->{split_sentences}) {
		my @syms = ();
		my @splitters = split(/\s+/, $self->{sentence_splitters});
		foreach my $item (@splitters) {
			$item =~ s/([^A-Za-z0-9 ])/\\$1/g;
			push (@syms,$item);
		}

		my $regexp = join ('|',@syms);

		my @sentences = split(/($regexp)/, $msg);
		return @sentences;
	}
	else {
		return $msg;
	}
}

sub formatMessage {
	my ($self,$msg) = @_;

	# Lowercase the string.
	$msg = lc($msg);

	# Get the words and run substitutions.
	my @words = split(/\s+/, $msg);
	my @new = ();
	foreach my $word (@words) {
		if (exists $self->{substitutions}->{$word}) {
			$word = $self->{substitutions}->{$word};
		}
		push (@new, $word);
	}

	# Reconstruct the message.
	$msg = join (' ',@new);

	# Remove punctuation and such.
	$msg =~ s/[^A-Za-z0-9 ]//g;
	$msg =~ s/^\s//g;
	$msg =~ s/\s$//g;

	return $msg;
}

sub person {
	my ($self,$msg) = @_;

	# Lowercase the string.
	$msg = lc($msg);

	# Get the words and run substitutions.
	my @words = split(/\s+/, $msg);
	my @new = ();
	foreach my $word (@words) {
		if (exists $self->{person}->{$word}) {
			$word = $self->{person}->{$word};
		}
		push (@new, $word);
	}

	# Reconstruct the message.
	$msg = join (' ',@new);

	return $msg;
}

sub tagFilter {
	my ($self,$reply,$id,$msg) = @_;

	# History tags.
	$reply =~ s/<input(\d)>/$self->{users}->{$id}->{history}->{input}->[$1]/g;
	$reply =~ s/<reply(\d)>/$self->{users}->{$id}->{history}->{reply}->[$1]/g;

	# Insert variables.
	$reply =~ s/<bot (.*?)>/$self->{botvars}->{$1}/g;
	$reply =~ s/<id>/$id/ig;

	# String modifiers.
	while ($reply =~ /\{(formal|uppercase|lowercase|sentence)\}(.*?)\{\/(formal|uppercase|lowercase|sentence)\}/i) {
		my ($type,$string) = ($1,$2);
		$type = lc($type);
		my $o = $string;
		$string = $self->stringUtil ($type,$string);
		$o =~ s/([^A-Za-z0-9 =<>])/\\$1/g;
		$reply =~ s/\{$type\}$o\{\/$type\}/$string/ig;
	}

	# Topic setters.
	if ($reply =~ /\{topic=(.*?)\}/i) {
		my $to = $1;
		$self->{users}->{$id}->{topic} = $to;
		# print "Setting topic to $to\n";
		$reply =~ s/\{topic=(.*?)\}//g;
	}

	# Variable setters?
	while ($reply =~ /\{\!(.*?)\}/i) {
		my $o = $1;
		my $data = $o;
		$data =~ s/^\s//g;
		$data =~ s/\s$//g;

		my ($type,$details) = split(/\s+/, $data, 2);
		my ($what,$is) = split(/=/, $details, 2);
		$what =~ s/\s//g; $is =~ s/^\s//g;
		$type =~ s/\s//g;
		$type = lc($type);

		# Stream this in.
		# print "Streaming in: ! $type $what = $is\n";
		$self->stream ("! $type $what = $is");
		$reply =~ s/\{\!$o\}//i;
	}

	# Sub-replies.
	while ($reply =~ /\{\@(.*?)\}/i) {
		my $o = $1;
		my $trig = $o;
		$trig =~ s/^\s//g;
		$trig =~ s/\s$//g;

		my $resp = $self->intReply ($id,$trig);

		$reply =~ s/\{\@$o\}/$resp/i;
	}

	# Run macros.
	while ($reply =~ /\&(.*?)\((.*?)\)/i) {
		my $rel = $1;
		my $data = $2;

		my ($object,$method) = split(/\./, $rel, 2);
		$method = 'default' unless defined $method;

		my $returned = '';

		if (defined $self->{macros}->{$object}) {
			$returned = &{$self->{macros}->{$object}} ($method,$data);
		}
		else {
			$returned = $self->{macro_failure} || 'ERR(Macro Failure!)';
		}

		$reply =~ s/\&(.*?)\((.*?)\)/$returned/i;
	}

	# Randomness.
	while ($reply =~ /\{random\}(.*?)\{\/random\}/i) {
		my $text = $1;
		my @options = ();

		# Pipes?
		if ($text =~ /\|/) {
			@options = split(/\|/, $text);
		}
		else {
			@options = split(/\s+/, $text);
		}

		my $rep = $options [ int(rand(scalar(@options))) ];
		$reply =~ s/\{random\}(.*?)\{\/random\}/$rep/i;
	}

	# Get/Set uservars?
	while ($reply =~ /<set (.*?)>/i) {
		my $o = $1;
		my $data = $o;
		my ($what,$is) = split(/=/, $data, 2);
		$what =~ s/\s$//g;
		$is =~ s/^\s//g;

		# Set it.
		if ($is eq 'undef') {
			delete $self->{uservars}->{$id}->{$what};
		}
		else {
			# print "Set $what to $is for $id\n";
			$self->{uservars}->{$id}->{$what} = $is;
		}

		$reply =~ s/<set (.*?)>//i;
	}
	while ($reply =~ /<(add|sub|mult|div) (.*?)>/i) {
		my $method = $1;
		my $o = $2;
		my $data = $o;
		my ($what,$is) = split(/=/, $data, 2);

		# See if this variable exists.
		if (!exists $self->{uservars}->{$id}->{$what}) {
			$self->{uservars}->{$id}->{$what} = 0; # Make it numeric
		}

		# Only accept numeric variables.
		if ($self->{uservars}->{$id}->{$what} =~ /[^0-9]/) {
			$reply =~ s/<$method $o>/(Var=NaN)/i;
			next;
		}
		elsif ($is =~ /[^0-9]/) {
			$reply =~ s/<$method $o>/(Value=NaN)/i;
			next;
		}

		# Do the operation.
		my $value = $self->{uservars}->{$id}->{$what} || 0;
		if ($method =~ /add/i) {
			$value += $is;
		}
		elsif ($method =~ /sub/i) {
			$value -= $is;
		}
		elsif ($method =~ /mult/i) {
			$value *= $is;
		}
		elsif ($method =~ /div/i) {
			$value /= $is;
		}

		$self->{uservars}->{$id}->{$what} = $value;

		$reply =~ s/<$method $o>//i;
	}
	while ($reply =~ /<get (.*?)>/i) {
		my $o = $1;
		my $data = $o;
		my $value = 'undefined';
		$value = $self->{uservars}->{$id}->{$data} if defined $self->{uservars}->{$id}->{$data};

		# print "Inserting $data ($value)\n";

		$reply =~ s/<get $o>/$value/i;
	}

	# Insert person tags.
	while ($reply =~ /\{person\}(.*?)\{\/person\}/i) {
		my $o = $1;
		my $data = $o;
		my $new = $self->person ($data);

		$reply =~ s/\{person\}(.*?)\{\/person\}/$new/i;
	}

	return $reply;
}

sub mergeWildcards {
	my ($self,$string,$stars) = @_;

	$string =~ s/<star(\d+)?>/$$stars[$1?$1:1] || ''/eig;

	return $string;
}

sub stringUtil {
	my ($self,$type,$string) = @_;

	if ($type eq 'uppercase') {
		return uc($string);
	}
	elsif ($type eq 'lowercase') {
		return lc($string);
	}
	elsif ($type eq 'sentence') {
		$string =~ s~\b(\w)(.*?)(\.|\?|\!|$)~\u$1\L$2$3\E~ig;
		return $string;
	}
	elsif ($type eq 'formal') {
		$string =~ s~\b(\w+)\b~\L\u$1\E~ig;
		return $string;
	}
	else {
		return $string;
	}
}

sub write {
	my $self = shift;
	my $to = shift || 'written.rs';

	my @file = ();

	# Write all replies to file.
	foreach my $topic (keys %{$self->{replies}}) {
		if ($topic eq 'random' || $topic =~ /^__that__/i) {
			# Don't add this in.
		}
		elsif ($topic eq '__begin__') {
			push (@file, "> begin");
			push (@file, "");
		}
		else {
			push (@file, "> topic $topic");
			push (@file, "");
		}

		# Get all triggers.
		foreach my $t (keys %{$self->{replies}->{$topic}}) {
			push (@file, "+ $t");

			# Get conditions
			for (my $i = 1; exists $self->{replies}->{$topic}->{$t}->{conditions}->{$i}; $i++) {
				my $line = $self->{replies}->{$topic}->{$t}->{conditions}->{$i};
				push (@file, "* $line");
			}

			# Get all the replies.
			for (my $i = 1; exists $self->{replies}->{$topic}->{$t}->{$i}; $i++) {
				push (@file, "- $self->{replies}->{$topic}->{$t}->{$i}");
			}

			# Get redirections.
			if (exists $self->{replies}->{$topic}->{$t}->{redirect}) {
				my $redir = $self->{replies}->{$topic}->{$t}->{redirect};
				push (@file, "\@ $redir");
			}

			# Get sys codes.
			if (exists $self->{replies}->{$topic}->{$t}->{system}->{codes}) {
				my $sys = $self->{replies}->{$topic}->{$t}->{system}->{codes};
				push (@file, "& $sys");
			}

			push (@file, "");
		}

		if ($topic eq 'random' || $topic =~ /^__that__/i) {
			# Don't add this in.
		}
		elsif ($topic eq '__begin__') {
			push (@file, "< begin");
			push (@file, "");
		}
		else {
			push (@file, "< topic");
			push (@file, "");
		}
	}

	open (OUT, ">$to") or return 0;
	print OUT join ("\n", @file);
	close (OUT);

	return 1;
}

1;
__END__

=head1 NAME

RiveScript - Rendering Intelligence Very Easily

=head1 SYNOPSIS

  use RiveScript;

  # Create a new RiveScript interpreter.
  my $rs = new RiveScript;

  # Define a macro.
  $rs->setSubroutine (weather => \&weather);

  # Load in some RiveScript documents.
  $rs->loadDirectory ("./replies");

  # Load in another file.
  $rs->loadFile ("./more_replies.rs");

  # Stream in yet more replies.
  $rs->stream ('! global split_sentences = 1');

  # Sort them.
  $rs->sortReplies;

  # Grab a response.
  my @reply = $rs->reply ('localhost','Hello RiveScript!');
  print join ("\n",@reply) . "\n";

=head1 DESCRIPTION

RiveScript is a simple input/response language. It is simple, easy to learn,
and mimics and perhaps even surpasses the power of AIML (Artificial Intelligence
Markup Language). RiveScript was initially created as a reply language for
chatterbots, but it has also been used for more complex things above and beyond
that.

RiveScript was originally known as Alpha but was reprogrammed to
add more flexibility and power to it. While their syntaces are similar,
Alpha code is not entirely compatible with RiveScript.

=head1 PUBLIC METHODS

=head2 new

Creates a new RiveScript instance. Pass in any defaults here.

=head2 setSubroutine (OBJECT_NAME => CODEREF)

Define a macro (see Object Macros)

=head2 loadDirectory ($DIRECTORY[, @EXTS])

Load a directory of RiveScript files. EXTS is optionally an array of file
extensions to load, in the format B<(.rs .txt .etc)>. Default is just ".rs"

=head2 loadFile ($FILEPATH[, $STREAM])

Load a single file. Don't worry about the STREAM argument, it is handled
in the stream() method.

=head2 stream ($CODE)

Stream RiveScript code directly into the module.

=head2 sortReplies

Sorts the replies. This is ideal for matching purposes. If you fail to
do so and just go ahead and call reply(), you'll get a nasty Perl warning.
It will sort them for you anyway, but it's always recommended to sort them
yourself. For example, if you sort them and then load new replies, the new
replies will not be matchable because the sort cache hasn't updated.

=head2 reply ($USER_ID, $MESSAGE[, %TAGS])

Get a reply from the bot. This will return an array. The values of this
array would be all the replies (i.e. if you use {nextreply} in a response
to return multiple).

B<%TAGS> is optionally a string of special reply tags, each value is a
boolean (1 or 0, all default to 0):

  scalar   -- Forces a scalar return of all replies found. The method
              will return a scalar rather than an array.
  no_split -- Ignore sentence-splitting when going into the reply.
              This is for special cases such as ";-)" (winking emoticon)
              where it is unmatchable because ; is a sentence-splitter.

  retry    -- You should NEVER set this argument. This is used internally
              so the module knows it's on a retry run (if a reply isn't
              found, it tries again but sets no_split to true).

=head2 search ($STRING)

Search all loaded replies for every trigger that STRING matches. Returns an
array of results, containing the trigger, what topic it was under, and the
reference to its file and line number.

=head2 write ([$FILEPATH])

Outputs the current contents of the loaded replies into a single file. This
is useful for if your application dynamically learns replies by editing the
loaded hashrefs. It will write all replies to the file under their own topics...
i.e. perfectly functional code. Comments and other unnessecary formatting is
ignored, because the module doesn't pay attention to them at loading time anyway.

The default path is to "written.rs"

See L<"DYNAMIC REPLIES">.

=head2 setGlobal (VARIABLE => VALUE, ...)

Set a global variable directly from Perl (alias for B<! global>)

=head2 setVariable (VARIABLE => VALUE, ...)

Set a botvariable (alias for B<! var>)

=head2 setSubstitution (BEFORE => AFTER, ...)

Set a substitution setting (alias for B<! sub>)

=head2 setUservar ($USER_ID, VARIABLE => VALUE, ...)

Set a user variable (alias for <set var=value>)

=head2 getUservars ([$USER_ID])

Get all uservars for a user. Returns a hashref of the variables. If you don't
pass in a $USER_ID, it will return a hashref of hashrefs for each user (first
level being their ID, second level being their variables).

=head1 PRIVATE METHODS

These methods are called on internally and should not be called by you.

=head2 debug ($MESSAGE)

Print a debug message.

=head2 intReply ($USER_ID, $MESSAGE)

This should not be called. Call B<reply> instead. This method assumes
that the variables are neatly formatted and may cause serious consequences
for passing in badly formatted data.

=head2 splitSentences ($STRING)

Splits string at the sentence-splitters and returns an array.

=head2 formatMessage ($STRING)

Formats the message (runs substitutions, removes punctuation, etc)

=head2 mergeWildcards ($STRING, $ARRAY)

Merges the values from ARRAY into STRING, where the items in ARRAY
correspond to a captured value from $1 to $100+. The first item in the
array should be blank; there is no such thing as a E<lt>star0E<gt>.

=head2 stringUtil ($TYPE, $STRING)

Called on for string format tags (uppercase, lowercase, formal, sentence).

=head1 FORMAT

RiveScript documents have a simple format: they're a line-by-line
language. The first symbol(s) are the commands, and the following text
is typically the command's data.

In its most simple form, a valid RiveScript entry looks like this:

  + hello bot
  - Hello human.

=head1 RIVESCRIPT COMMANDS

The following are the commands that RiveScript supports.

=over 4

=item B<! (Definition)>

The ! command is for definitions. These are one of the few stand-alone
commands (ones that needn't be part of a bigger reply group). They are
to define variables and arrays. Their format is as follows:

  ! type variable = value

  type     = the variable type
  variable = the name of the variable
  value    = the variable's value

The supported types are as follows:

  global  - Global settings (top-level things)
  var     - BotVariables (i.e. the bot's name, age, etc)
  array   - An array
  sub     - A substitution pattern
  person  - A person substitution.
  addpath - Add an include path
  include - An include method

Some examples:

  // Set global vars
  ! global debug = 1
  ! global split_sentences = 1
  ! global sentence_splitters = . ! ; ?

  // Setup a handler for macro failures.
  ! global macro_failure = <b>ERROR: Macro Failure</b>

  // Set bot vars
  ! var botname   = Casey Rive
  ! var botage    = 14
  ! var botgender = male

  // Some substitutions
  ! sub can't = can not
  ! sub i'm   = i am

  // Person substitutions
  ! person i   = you
  ! person you = me
  ! person am  = are
  ! person are = am

  // Add a path to find libraries.
  ! addpath C:/MyRsLibraries

  // Include a library of arrays
  ! include English/EngVerbs.rsl

  // Include a package of objects
  ! include DateTime.rsp

B<Note:> For arrays, you can have multi-word items if you separate the entries
with a pipe ("|") symbol rather than a space.

B<Note:> To delete a variable, set its value to "undef" and its internal hashref
key will be deleted altogether.

See also: L<"ENVIRONMENTAL VARIABLES"> and L<"PERSON SUBSTITUTION">.

=item B<E<lt> and E<gt> (Label)>

The E<lt> and E<gt> commands are for defining labels. A label is used to treat
a part of code differently. Currently there are three uses for labels:
B<begin>, B<topic>, and B<object>. Example usage:

  // Define a topic
  > topic some_topic_name

    // there'd be some triggers here

  < topic
  // close the topic

=item B<+ (Trigger)>

The + command is the basis for all triggers. The + command is what the
user has to say to activate the reply set. In the example,

  + hello bot
  - Hello human.

The user would say "hello bot" only to get a "Hello human." back.

=item B<% (Previous)>

The % command is for drawing a user back to complete a thought. You
might say it's sort of like E<lt>thatE<gt> in AIML. Example:

  + ask me a question
  - Do you have any pets?

  + yes
  % do you have any pets
  - What kind of pet?

  // and so-on...

=item B<- (Response)>

The - command is the response. The - command has several uses, depending
on its context. For example, in the "hello bot/hello human" example, one
+ with one - gets a one-way question/answer scenario. If more than one -
is used, a random one is chosen (and some may be weighted). There are many
other uses that we'll get into later.

=item B<^ (Continue)>

The ^Continue command is for extending the previous command down a line.

The commands that can be continued with ^Continue:

  ! global
  ! var
  ! array
  + trigger
  % previous
  - response
  @ redirection

Sometimes your -REPLY is too long to fit on one line, and you don't like
the idea of having a horizontal scrollbar on your text editor.
The ^ command will continue on from the last -REPLY. For example:

  + tell me a poem
  - Little Miss Muffit sat on her tuffet\s
  ^ in a nonchalant sort of way.\s
  ^ With her forcefield around her,\s
  ^ the Spider, the bounder,\s
  ^ is not in the picture today.

Here are some examples of the other uses of ^Continue:

  ! array colors  = red blue green yellow cyan fuchsia
  ^ white black gray grey orange pink
  ^ turqoise magenta gold silver

  ! var quote = How much wood would a woodchuck
  ^ chuck if a woodchuck could chuck wood?

  + how much wood would a woodchuck\s
  ^ chuck if a woodchuck could chuck wood
  - A whole forest. ;)

  + how much wood
  @ how much wood would a woodchuck\s
  ^ chuck if a woodchuck could chuck wood

=item B<@ (Redirect)>

The @ command is for directing one trigger to another. For example, there
may be complicated ways people have of asking the same thing, and you don't
feel like making your main trigger handle all of them.

  + my name is *
  - Nice to meet you, {formal}<star1>{/formal}.

  + people around here call me *
  @ my name is <star1>

Redirections can also be used inline. See the L<"TAGS"> section for more details.

=item B<* (Conditions)>

The * command is used for checking conditionals. The format is:

  * variable = value => say this

For example, you might want to make a condition to differentiate male from
female users.

  + am i a guy or a girl
  * gender=male => You're a guy.
  * gender=female => You're a girl.
  - I don't think you ever told me what you are.

You can perform the following operations on variable checks:

  =  equal to
  != not equal to
  <  less than
  <= less than or equal to
  >  greater than
  >= greater than or equal to
  ?  returns true if the var is even defined

B<Note:> If you want a condition to check the value of a bot variable, you must
prepend a # sign on the variable name. For instance:

  + is your name still soandso
  * #name = Soandso => That's still my name.
  - No, I changed it.

That would check the B<botvar> "name", not the B<uservar>, because of the
supplied # sign.

=item B<& (Perl)>

Sometimes RiveScript isn't powerful enough to do what you want. The & command
will execute Perl codes to handle these cases. Be sure to read through this
whole manpage before resorting to Perl, though. RiveScript has come a long way
since it was known as Alpha.

  + what is 2 plus 2
  - 500 Internal Error.
  & $reply = '2 + 2 = 4';

=item B<// (Comments)>

The comment syntax is //, as it is in other programming languages. Also,
/* */ comments may be used to span over multiple lines.

  // A one-line comment

  /*
    this comment spans
    across multiple lines
  */

=back

=head1 RIVESCRIPT HOLDS THE KEYS

The RiveScript engine was designed for your RiveScript brain to hold most of the
control. As little programming on the Perl side as possible has made it so that
your RiveScript can define its own variables and handle what it wants to. See
L<"A GOOD BRAIN"> for tips on how to approach this.

=head1 COMPLEXITIES OF THE TRIGGER

The + command can be used for more complex things as a simple, 100% dead-on
trigger. This part is passed through a regexp. Therefore, any regexp things
can be used in the trigger.

B<Note:> an asterisk * is always converted into (.*?) regardless of its context.
Keep this in mind.

B<Alternations:> You can use alternations in the triggers like so:

  + what (s|is) your (home|office|cell) phone number

Anything inside of parenthesis, or anything matched by asterisks, can be
obtained through the tags E<lt>star1E<gt> to E<lt>star100E<gt>. For example (keeping in mind
that * equals (.*?):

  + my name is *
  - Nice to meet you, <star1>.

B<Optionals:> You can use optional words in a trigger. These words don't have
to exist in the user's message but they I<can>. Example:

  + what is your [home] phone number
  - You can call me at 555-5555.

So that would match "I<what is your phone number>" as well as
"I<what is your home phone number>"

Optionals can have alternations in them too.

  + what (s|is) your [home|office|cell] phone number

B<Arrays:> This is why it's good to define arrays using the !define tag. The
best way to explain how this works is by example.

  // Make an array of color names
  ! array colors = red blue green yellow white black orange

  // Now the user can tell us their favorite color from the array
  + my favorite color is (@colors)
  - Really! Mine is <star1> too!

If you want an array to be matchable, enclose it in parenthesis. This will allow
its value to be put into a E<lt>starE<gt> tag, as in the above example. If you
don't include the parenthesis, its value won't be matchable. For an example of
the difference:

  If the input is "sometimes I am a tool"...

  ! array be = am are is was were

  + *\bi @be *
      <star1> = ''
      <star2> = 'a tool'

  + *\bi (@be) *
      <star1> = 'sometimes'
      <star2> = 'am'
      <star3> = 'a tool'

It turns your array into regexp form, B<(?:red|blue|green|yellow|...)> before matching
so it saves you a lot of work there. Not to mention arrays can be used in any number
of triggers! Just imagine how many triggers you can come up with where a color name
would be needed...

=head1 COMPLEXITIES OF THE RESPONSE

As mentioned above, the - command has many many uses.

B<One-way question/answer:> A single + and a single - will lead to a dead-on
question and answer reply.

B<Random Replies:> A single + with multiple -'s will yield random results
from among the responses. For example:

  + hello
  - Hey.
  - Hi.
  - Hello.

Would randomly return any of those three responses.

B<Conditional Fallback:> When using conditionals, you should always provide
at least one response to fall back on, in case every conditional returns false.

B<Perl Code Fallback:> When executing Perl code, you should always have a response
to fall back on [even if the Perl is going to redefine $reply for itself]. This is
in case of an eval error and the Perl couldn't do its thing.

B<Weighted Responses:> Yes, with random responses you can weight them! Responses
with higher weight will have a better chance of being chosen over ones with a low
weight. For example:

  + hello
  - Hello, how are you?{weight=49}
  - Yo, wazzup dawg?{weight=1}

In this case, "Hello, how are you?" will almost always be sent back. A 1 in 50
chance would return "Yo, wazzup dawg?" instead.

(as a side note: you don't need to set a weight to 1; 1 is implied for any
response without weight. Weights of less than 1 aren't acceptable)

=head1 BEGIN STATEMENT

B<The BEGIN file is the first reply file loaded in a loadDirectory call.>
If a "begin.rs" file exists in the directory being loaded, it is included first.

B<Note:> BEGIN statements are not required. That being said, begin statements
are executed before any request.

B<How to define a BEGIN statement>

  > begin
    + request
    - {ok}
  < begin

Begin statements are sort of like topics, but are always called first. If the response
given contains {ok} in it, then the module knows it's allowed to get a reply.
Also note that {ok} is replaced with the response. In this way, B<begin> might be
useful to format all responses in one way. For a good example:

  > begin

    // Don't give a reply if the bot is down for maintenance.
    + request
    * down=yes => The bot is currently deactivated for maintenance.
    - <font color="red"><b>{ok}</b></font>

  < begin

That would give the reply about the bot being under maintenance if the variable
"down" equals "yes." Else, it would give a response in red bold font.

You can also put tags in to modify the returned responses of the bot. For example,
the bot can "type" differently depending on a variable "mood" (see L<"TAGS">)

  > begin
    + request
    * mood = happy  => {ok}
    * mood = sad    => {lowercase}{ok}{/lowercase}
    * mood = angry  => {uppercase}{ok}{/uppercase}
    * mood = pissed => {@not talking}
    - {ok}

    + not talking
    - I'm not in a talkative mood.
    - I'm not too happy right now.
    - I don't want to talk right now.
  < begin

B<Note:> At the time being, the only trigger that BEGIN ever receives is "request"

The "begin.rs" file is also where you would place your B<!include> statements to
make sure that they're included before any other files.

=head1 TOPICS

Topics are declared in a way similar to the BEGIN statement. The way to declare
and close a topic is generally as follows:

  > topic TOPICNAME
    ...
  < topic

The topic name should be unique, and only one word.

B<The Default Topic:> The default topic name is "random"

B<Setting a Topic:> To set a topic, use the {topic} tag (see L<"TAGS"> below). Example:

  + i hate you
  - You're not very nice. I'm going to make you apologize.{topic=apology}

  > topic apology
    + *
    - Not until you admit that you're sorry.

    + sorry
    - Okay, I'll forgive you.{topic=random}
  < topic

Always set topic back to "random" to break out of a topic.

=head1 OBJECT MACROS

Special macros (Perl routines) can be defined and then utilized in your RiveScript
code.

=head2 Inline Objects

New with version 0.04 is the ability to define objects directly within the RiveScript code. Keep in mind
that the code for your object is evaluated local to RiveScript. That being said, basic tips to
follow to make an object work:

  1) If it uses any module besides strict and warnings, that module must be explicitely
     declared within your object with a 'use' statement.
  2) If your object refers to any variables global to your main program, 'main::' must
     be prepended (i.e. '$main::hashref->{key}')
  3) If your object refers to a subroutine of your main program, 'main::' must be prepended
     (i.e. '&main::reload()')

The basic way is to do it like this:

  > object fortune
    my ($method,$msg) = @_;

    my @fortunes = (
       'You will be rich and famous',
       'You will meet a celebrity',
       'You will go to the moon',
    );

    return $fortunes [ int(rand(scalar(@fortunes))) ];
  < object

Note: the B<closing tag> (last line in the above example) is required for objects. An object isn't included until the closing tag
is found.

=head2 Define an Object from Perl

This is done like so:

  # Define a weather lookup macro.
  $rs->setSubroutine (weather => \&weather_lookup);

The code of the subroutine would be basically the same as it would be in the example for Inline Objects.
Basically, think of the "E<gt> object fortune" as "sub fortune {" and the "E<lt> object" as "}" and it's a little
easier to visualize. ;)

=head2 Call an Object

You can use a macro within a reply such as this example:

  + give me the local weather for *
  - Weather for &weather.cityname(<star1>):\n\n
  ^ Temperature: &weather.temp(<star1>)\n
  ^ Feels Like: &weather.feelslike(<star1>)

The subroutine "weather_lookup" will receive two variables: the method and the
arguments. The method would be the bit following the dot (i.e. "cityname",
"temp", or "feelslike" in this example). The arguments would be the value of
<star1>.

Whatever weather_lookup would return is inserted into the reply in place of the
macro call.

B<Note:> If a macro does not exist, has faulty code, or does not return a reply,
the contents of global "macro_failure" will be inserted instead. At this time the
module is unable to tell you which of the three errors is the cause.

=head1 TAGS

Special tags can be inserted into replies and redirections. Tags either have
E<lt>angle bracketsE<gt> or {curly brackets}. The E<lt>angle bracketsE<gt> are
generally for things that insert something back into the message, such as
E<lt>starE<gt>, E<lt>idE<gt>, or E<LT>input5E<gt>. The {curly brackets} are
generally for things that operate in silence and don't output anything, such
as {topic} which modifies the topic, or they're modifiers of text, such as
{random} and {uppercase}.

Also, tags closely tied to others in function will have the same symbols as
them. For instance, E<lt>setE<gt> doesn't output anything but is close in
function to E<lt>getE<gt>. This is just an explanation of my choice of symbols.
That being said, you can ignore these two paragraphs. ;)

The supported tags are as follows:

=head2 E<lt>starE<gt>, E<lt>star1E<gt> - E<lt>star100E<gt>

These tags will insert the values of $1 to $100, as matched in the regexp, into
the reply. They go in order from left to right. <star> is an alias for <star1>.

=head2 E<lt>input1E<gt> - E<lt>input9E<gt>; E<lt>reply1E<gt> - E<lt>reply9E<gt>

Inserts the last 1 to 9 things the user said, and the last 1 to 9 things the bot
said, respectively. Good for things like "You said hello and then I said hi and then
you said what's up and then I said not much"

=head2 E<lt>idE<gt>

Inserts the user's ID.

=head2 E<lt>botE<gt>

Insert a bot variable (defined with B<! var>).

  + what is your name
  - I am <bot name>, created by <bot companyname>.

This variable can also be used in triggers.

  + my name is <bot name>
  - <set name=<bot name>>What a coincidence, that's my name too!

=head2 E<lt>getE<gt>, E<lt>setE<gt>

Get and set a user variable. These are local variables for each user.

  + my name is *
  - <set name={formal}<star1>{/formal}>Nice to meet you, <get name>!

  + who am i
  - You are <get name> aren't you?

=head2 E<lt>addE<gt>, E<lt>subE<gt>, E<lt>multE<gt>, E<lt>divE<gt>

Add, subtract, multiply and divide numeric variables, respectively.

  + give me 5 points
  - <add points=5>You have received 5 points and now have <get points> total.

If the variable is undefined, it is set to 0 before the math is done on it.
If you try to modify a non-numerical variable, the operation will fail and a
little note of B<(Var=NaN)> will appear in place of the tag.

Likewise, if you try to modify a variable by inputting a non-numerical value
into the tag, B<(Value=NaN)> would be returned instead. Two examples of how
to trigger these:

  + add 5 to my name
  - <add name=5>Tried.

  + add hello to my age
  - <add age=hello>Tried.

Where "name" would be the user's name and "age" is their (numerical) age.

=head2 {topic=...}

The topic tag. This will set the user's topic to something else (see L<"TOPICS">). Only
one of these should be in a response, and in the case of duplicates only the first
one is evaluated.

=head2 {nextreply}

Breaks the reply into two (or more) parts there. Will cause the B<reply> method
to return multiple responses.

=head2 {weight=...}

A -REPLY can have a weight tag applied to it to change the probability of it being
chosen (when there is more than one reply that could be randomly chosen).
See L<"COMPLEXITIES OF THE RESPONSE">.

=head2 {@...}

An inline redirection. These work like normal redirections, except are inserted
inline into a reply.

  + * or something
  - Or something. {@<star1>}

=head2 {!...}

An inline definition. These can be used to (re)set variables. This tag is invisible
in the final response of the bot; the changes are made silently.

=head2 {random}...{/random}

Will insert a bit of random text. This has two syntaxes:

  Insert a random word (separate by spaces)
  {random}red blue green yellow{/random}

  Insert a random phrase (separate by pipes)
  {random}Yes sir.|No sir.{/random}

=head2 {person}...{/person}

Will take the enclosed text and run person substitutions on them (see
L<"PERSON SUBSTITUTION">).

=head2 {formal}...{/formal}

Will Make Your Text Formal

=head2 {sentence}...{/sentence}

Will make your text sentence-cased.

=head2 {uppercase}...{/uppercase}

WILL MAKE THE TEXT UPPERCASE.

=head2 {lowercase}...{/lowercase}

will make the text lowercase.

=head2 {ok}

This tag is used only with the L<"BEGIN STATEMENT">. It tells the interpreter
that it's okay to go and get a reply.

=head2 \s

Inserts a white space. Simple as that. This is needed if you use the -^ combo
for continuing a reply. RiveScript does not assume a space between the texts
of the two tags.

=head2 \n

Inserts a newline. Note that this tag is interpreted at the time of grabbing
a reply(). Other than that, it exists in memory as a literal '\n' (or "\\n")

=head1 ENVIRONMENTAL VARIABLES

Environmental variables are kept as "botvariables" (i.e. they can be retrieved with
the E<lt>botE<gt> tag). The variable names all begin with "ENV_" and are in uppercase.

=head2 RiveScript Environment Variables

  ENV_OS         = The operating system RiveScript is running on.
  ENV_APPVERSION = The version of RiveScript used.
  ENV_APPNAME    = A user-agent style string that looks like "RiveScript/0.08"

=head2 Perl Environment Variables

All the environment variables available to your Perl script are kept under B<ENV_SYS_>
with their original names following. For example, B<ENV_SYS_PATH> would be the %PATH%
variable on Windows.

=head2 Set Environment Variables

Currently, RiveScript's syntax does not allow the modification of any variable
beginning with "env_". If you absolutely must override one of these variables for
any reason at all, you can call the B<setVariable()> method to do so.

=head1 PERSON SUBSTITUTION

The {person} tag can be used to perform substitutions between 1st- and 2nd-person
adjectives (see L<"TAGS">).

You define these with the !define tag in a similar fashion as how you define
substitution data. For example:

  ! person i     = you
  ! person my    = your
  ! person mine  = yours
  ! person me    = you
  ! person am    = are
  ! person you   = I
  ! person your  = my
  ! person yours = mine
  ! person are   = am

Then use the {person} tag in a response. The enclosed text will swap the words
listed with the !person tags. For instance:

  + do you think *
  - What if I do think {person}<star>{/person}?

  "Do you think I am a bad person?"
  "What if I do think you are a bad person?"

See, that's the use of this tag. Otherwise the bot would have replied "What if I
do think B<I am> a bad person?" and not make very much sense.

B<Note:> RiveScript does NOT assume any person substitutions. Your RiveScript
code must define them as exampled above.

=head1 DYNAMIC REPLIES

A function added in version 0.07 is to B<write()> the loaded replies into a
single RS file. This is useful for if your program dynamically learns new
replies.

This section of the POD is devoted to explaining the setup of the internal
hashrefs of the RiveScript instance.

=head2 $rs->{replies}

This hashref contains the meat of the loaded replies. The first keys here
are the topics (keep in mind that 'random' is the default topic). For replies
that had %PREVIOUS in them, their topics are '__that__(bots last message, lowercase
and without punctuation)' and that the data from BEGIN is in '__begin__'

So for example, B<$rs-E<gt>{replies}-E<gt>{random}> is where replies under the default
topic are, while B<$rs-E<gt>{replies}-E<gt>{apology}> is where replies under the
'apology' topic are, et cetera.

The sub-keys under a topic are the triggers. These are literally the strings
you'd find in the file at the + command.

For example, B<$rs-E<gt>{replies}-E<gt>{random}-E<gt>{'my favorite color is (@colors)'}>

=head2 Trigger Keys

The following keys are used under trigger hashrefs ($rs->{replies}->{$topic}->{$trigger})

B<1..n> - The -REPLIES under the trigger. The first - is position 1, and they increment
from there.

B<redirect> - The data from the @redirect command. Since RiveScript only supports a single
@redirect in a message, this always has a single value.

B<conditions-E<gt>{1..n}> - The data from the *condition commands. This is in similar format
to the -replies, where 1 is the first condition.

B<system-E<gt>{codes}> - The contents of any system codes provided by &perl commands.

=head2 Sorted Arrays

The first keys under B<$rs-E<gt>{array}> are the topic names, as they are in $rs->{replies}.
But the contents of each topic key is an array ref of the sorted triggers.

Generally, you shouldn't have to worry about modifying this variable directly--just
call sortReplies() and it will manage it automatically.

=head2 Examples

  // RiveScript Code
  + my name is *
  - <star>, nice to meet you!
  - Nice to meet you, <star>.

  # Perl code. Get the value of the second reply.
  $rs->{replies}->{random}->{'my name is *'}->{2}

  // RiveScript Code
  > topic favorites
    + *(@colors)*
    - I like <star2> too. :-)
    & &main::log('<id> likes <star2>')
  < topic

  # Perl code. Get the perl data from that trigger.
  $rs->{replies}->{favorites}->{'*(@colors)*'}->{system}->{codes}

  // RiveScript Code
  + *
  % whos there
  - <star> who?

  # Perl code. Access this one's reply.
  $rs->{replies}->{'__that__whos there'}->{1}

=head1 INCLUDED FILES

B<Recommended Practice> is to put all your B<!include> statements inside your "begin.rs"
file, as this file is loaded in first. The "include" statement is for including common
libraries or packages.

=head2 RiveScript Libraries

RiveScript Libraries (B<.rsl> extention) are special RiveScript documents which contain
nothing but B<!arrays> and B<!substitutions> and the like. For instance, you could make
a language library which could contain arrays of verbs and their conjugations.

=head2 RiveScript Packages

RiveScript Packages (B<.rsp> extension) are special RiveScript documents which contain
one (or more) objects. For example, you might create a RiveScript package full of objects
for returning the date and time in different formats.

=head2 RiveScript Include Search Path

The current RiveScript Includes search path is an array of Perl's @INC, with "/RiveScript"
tacked on the end of it. Also "." is an include path (the working directory of the script
running RiveScript).

You can use the B<!addpath> directive to add new search paths.

=head1 RESERVED VARIABLES

The following are all the reserved variables and values within RiveScript's
processor.

=head2 Reserved Global Variables

These variables cannot be overwritten with the B<! global> command:

  reserved replies array syntax streamcache botvars uservars
  botarrays sort users substitutions

=head2 Reserved Topic Names

The following topic names are reserved and should never be (re)created in
your RiveScript files:

  __begin__   (used for the BEGIN method)
  __that__*   (used for the %PREVIOUS command)

=head1 A GOOD BRAIN

Since RiveScript leaves a lot of control up to the brain and not the Perl code,
here are some general tips to follow when writing your own brain:

B<Make a config file.> This would probably be named "config.rs" and it would
handle all your definitions. For example it might look like this:

  // Set up globals
  ! global debug = 0
  ! global split_sentences = 1
  ! global sentence_splitters = . ! ; ?

  // Set a variable to say that we're active.
  ! var active = yes

  // Set up botvariables
  ! var botname = Rive
  ! var botage = 5
  ! var company = AiChaos Inc.
  // note that "bot" isn't required in these variables,
  // it's only there for readibility

  // Set up substitutions
  ! sub won't = will not
  ! sub i'm = i am
  // etc

  // Set up arrays
  ! array colors = red green blue yellow cyan fuchsia ...

Here are a list of all the globals you might want to configure.

  split_sentences    - Whether to do sentence-splitting (1 or 0, default 1)
  sentence_splitters - Where to split sentences at. Separate items with a single
                       space. The defaults are:   ! . ? ;
  macro_failure      - Text to be inserted into a bot's reply when a macro fails
                       to run (or return a reply).
  debug              - Debug mode (1 or 0, default 0)

B<Make a begin file.> Create a file called "begin.rs" -- there are several reasons
for doing so.

For one, you should use this file for B<!include> statements if you want your brain
to use some common libraries or packages. Secondly, you can use the B<E<gt>BEGIN>
statement to setup a handler for incoming messages.

Your begin file could check the "active" variable we set in the config file to
decide if it should give a reply.

  > begin
    + request
    * active=no => Sorry but I'm deactivated right now!
    - {ok}
  < begin

These are the basic tips, just for organizational purposes.

=head1 SEE OTHER

You might want to take a look at L<Chatbot::Alpha>, this module's predecessor.

=head1 KNOWN BUGS

None yet known.

=head1 CHANGES

  Version 0.14
  - {formal} and {sentence} tags fixed. They both use regexp's now. {sentence} can
    take multiple sentences with no problem.
  - In a BEGIN statement, {topic} tags are handled first. In this way, the BEGIN
    statement can force a topic before getting a reply under the user's current topic.
  - Fixed a bug with "blank" commands while reading in a file.
  - Fixed a bug with the RiveScriptLib Search Paths.

  Version 0.13
  - The BEGIN/request statement has been changed. The user that makes the "request"
    is the actual user--no longer "__rivescript__", so user-based conditionals can
    work too. Also, request tags are not processed until the reply-getting process
    is completed. So tags like {uppercase} can modify the final returned reply.

  Version 0.12
  - Migrated to RiveScript:: namespace.

  Version 0.11
  - When calling loadDirectory, a "begin.rs" file is always loaded first
    (provided the file exists, of course!)
  - Added support for "include"ing libraries and packages (see "INCLUDED FILES")

  Version 0.10
  - The getUservars() method now returns a hashref of hashrefs if you want the
    vars of all users. Makes it a little easier to label each set of variables
    with the particular user involved. ;)
  - Cleaned up some leftover print statements from my debugging in version 0.09
    (sorry about that--again!)
  - Made some revisions to the POD, fixed some typo's, added {weight} and {ok}
    to the TAGS section.

  Version 0.09
  - $1 to $100+ are now done using an array rather than a hash. Theoretically
    this allows any number of stars, even greater than 100.
  - Arrays in triggers have been modified. An array in parenthesis (the former
    requirement) will make the array matchable in <star#> tags. An array outside
    of parenthesis makes it NOT matchable.
  - Minor code improvements for readibility purposes.

  Version 0.08
  - Added <add>, <sub>, <mult>, and <div> tags.
  - Added environmental variable support.
  - Extended *CONDITION to support inequalities
  - Botvars in conditions must be explicitely specified with # before the varname.
  - Added "! person" substitutions
  - Added {person} tag

  Version 0.07
  - Added write() method
  - reply() method now can take tags to force scalar return or to ignore
    sentence-splitting.
  - loadDirectory() method can now take a list of specific file extensions
    to look for.
  - Cleaned up some leftover debug prints from last release (sorry about that!)

  Version 0.06
  - Extended ^CONTINUE to cover more commands
  - Added \s and \n tags
  - Revised POD

  Version 0.05
  - Fixed a bug with optionals. If they were used at the start or end
    of a trigger, the trigger became unmatchable. This has been fixed
    by changing ' ' into '\s*'

  Version 0.04
  - Added support for optional parts of the trigger.
  - Begun support for inline objects to be created.

  Version 0.03
  - Added search() method.
  - <bot> variables can be inserted into triggers now (for example having
    the bot reply to its name no matter what its name is)

  Version 0.02
  - Fixed a regexp bug; now it stops searching when it finds a match
    (it would cause errors with $1 to $100)
  - Fixed an inconsistency that didn't allow uservars to work in
    conditionals.
  - Added <id> tag, useful for objects that need a unique user to work
    with.
  - Fixed bug that lets comments begin with more than one set of //

  Version 0.01
  - Initial Release

=head1 TO-DO LIST

Feel free to offer any ideas. ;)

=head1 SPECIAL THANKS

Special thanks goes out to B<jeffohrt> and B<harleypig> of the AiChaos
Forum for helping so much with the development of RiveScript.

=head1 AUTHOR

  Cerone Kirsle, kirsle --at-- rainbowboi.com

=head1 COPYRIGHT AND LICENSE

    RiveScript - Rendering Intelligence Very Easily
    Copyright (C) 2006  Cerone J. Kirsle

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
