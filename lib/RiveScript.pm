package RiveScript;

use strict;
no strict 'refs';
use warnings;
use RiveScript::Brain;
use RiveScript::Parser;
use RiveScript::Util;
use Data::Dumper;

our $VERSION = '1.00';

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto || 'RiveScript';

	my $self = {
		debug       => 0,
		parser      => undef, # RiveScript::Parser Object
		reserved    => [      # Array of reserved (unmodifiable) keys.
			qw (reserved replies array syntax streamcache botvars uservars botarrays
			sort users substitutions library parser thatarray),
		],
		replies     => {},    # Replies
		array       => {},    # Sorted replies array
		thatarray   => [],    # Sorted "that" array (for %PREVIOUS)
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
		evals       => undef, # Needed by RiveScript::Parser

		# Enable/Disable Certain RS Commands
		strict_type => 'allow_all', # deny_some, allow_some, allow_all
		cmd_allowed => [],
		cmd_denied  => [],

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

sub denyMode {
	my ($self,$mode) = @_;

	if ($mode =~ /^(deny_some|allow_some|allow_all)$/i) {
		$self->{strict_type} = lc($mode);
	}
	else {
		warn "Invalid mode \"$mode\" -- must be deny_some, allow_some, or allow_all";
	}
}

sub deny {
	my ($self,@cmd) = @_;

	if ($self->{strict_type} ne 'deny_some') {
		warn "Adding commands to deny list but denyMode isn't deny_some!";
	}

	push (@{$self->{cmd_denied}}, @cmd);
}

sub allow {
	my ($self,@cmd) = @_;

	if ($self->{strict_type} ne 'allow_some') {
		warn "Adding commands to allow list but denyMode isn't allow_some!";
	}

	push (@{$self->{cmd_allowed}}, @cmd);
}

sub makeParser {
	my $self = shift;

	$self->{parser} = undef;
	$self->{parser} = new RiveScript::Parser (
		reserved => $self->{reserved},
		debug    => $self->{debug},
	);

	# Transfer all RS variables.
	foreach my $key (keys %{$self}) {
		$self->{parser}->{$key} = $self->{$key};
	}
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
	my $self   = shift;
	my $file   = $_[0] || '(Streamed)';
	my $stream = $_[1] || 0;

	# Create a parser for this file.
	$self->makeParser;

	# Streamed Replies?
	if ($stream) {
		$self->{parser}->{streamcache} = $self->{streamcache};
	}

	# Read in this file.
	$self->{parser}->loadFile (@_);

	# Eval codes?
	if (length $self->{parser}->{evals}) {
		my $eval = eval ($self->{parser}->{evals}) || $@;
		delete $self->{parser}->{evals};
	}

	# Copy variables over.
	foreach my $key (keys %{$self->{parser}}) {
		$self->{$key} = $self->{parser}->{$key};
	}

	# Undefine the object.
	$self->{parser} = undef;

	return 1;
}

sub sortReplies {
	my ($self) = @_;

	# Create the parser.
	$self->makeParser;

	# Sort the replies.
	$self->{parser}->sortReplies();

	# Save variables.
	foreach my $key (keys %{$self->{parser}}) {
		$self->{$key} = $self->{parser}->{$key};
	}

	$self->{parser} = undef;

	# Get an idea of the number of replies we have.
	my $replyCount = 0;
	foreach my $topic (keys %{$self->{array}}) {
		$replyCount += scalar(@{$self->{array}->{$topic}});
	}

	$self->{replycount} = $replyCount;
	$self->{botvars}->{ENV_REPLY_COUNT} = $replyCount;

	return 1;
}

sub reply {
	return RiveScript::Brain::reply (@_);
}

sub intReply {
	return RiveScript::Brain::intReply (@_);
}

sub search {
	return RiveScript::Brain::search (@_);
}

sub splitSentences {
	my ($self,$msg) = @_;

	if ($self->{split_sentences}) {
		return RiveScript::Util::splitSentences ($self->{sentence_splitters},$msg);
	}
	else {
		return $msg;
	}
}

sub formatMessage {
	my ($self,$msg) = @_;
	return RiveScript::Util::formatMessage ($self->{substitutions},$msg);
}

sub person {
	my ($self,$msg) = @_;
	return RiveScript::Util::person ($self->{person},$msg);
}

sub tagFilter {
	return RiveScript::Util::tagFilter (@_);
}

sub tagShortcuts {
	return RiveScript::Util::tagShortcuts (@_);
}

sub mergeWildcards {
	my ($self,$string,$stars) = @_;
	return RiveScript::Util::mergeWildcards ($string,$stars);
}

sub stringUtil {
	my ($self,$type,$string) = @_;
	return RiveScript::Util::stringUtil ($type,$string);
}

sub write {
	my $self = shift;
	my $to = $_[0] || 'written.rs';

	# Create the parser.
	$self->makeParser;

	# Write.
	$self->{parser}->write (@_);

	# Destroy the parser.
	$self->{parser} = undef;
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

  # Load some replies.
  $rs->loadDirectory ("./replies");

  # Load in another file.
  $rs->loadFile ("./more_replies.rs");

  # Stream in even more RiveScript code.
  $rs->stream (q~! global split_sentences = 1~);

  # Sort all the loaded replies.
  $rs->sortReplies;

  # Grab a response.
  my @reply = $rs->reply ('localscript', 'Hello RiveScript!');
  print join ("\n", @reply), "\n";

=head1 DESCRIPTION

RiveScript is a simple input/response language. It has a simple, easy-to-learn syntax,
yet it is more powerful even than Dr. Wallace's AIML (Artificial Intelligence Markup Language).
RiveScript was created as a reply language for chatterbots, but it has been used for
more complex things above and beyond that.

=head1 PERL PACKAGE

This part of the manpage documents the methods of the Perl RiveScript library. The RiveScript
language specifications are below: see L<"RIVESCRIPT">.

=head2 Public Methods

=over 4

=item new

Creates a new RiveScript instance.

=item setSubroutine (OBJECT_NAME => CODEREF)

Define an object macro (see L<"Object Macros">)

=item loadDirectory ($DIRECTORY[, @EXTS])

Load a directory of RiveScript files. C<@EXTS> is optionally an array of file extensions
to load, in the format C<(.rs .txt .etc)>. Default is just ".rs"

=item loadFile ($FILEPATH[, $STREAM])

Load a single RiveScript file. Don't worry about the C<$STREAM> argument, it is handled
in the C<stream()> method.

=item stream ($CODE)

Stream RiveScript codes directly into the module.

=item sortReplies

Sorts all the loaded replies. This is necessary for reply matching purposes. If you fail
to call this method yourself, it will be called automatically with C<reply()>, but not without
a nasty Perl warning. It's better to always sort them yourself, for example if you load in
new replies later, they won't be matchible unless a new C<sortReplies> is called.

=item reply ($USER_ID, $MESSAGE[, %TAGS])

Get a reply from the bot. This will (normally) return an array. The values of the array
would be all the replies to that message (i.e. if you use the C<{nextreply}> tag in a
response, or if you pass in multiple sentences).

C<%TAGS> is optionally a hash of special reply tags. Each value is boolean.

  scalar   = Forces the return value into a scalar instead of an array
  no_split = Don't run sentence-splitters on the message.
  retry    = INTERNAL. Tells the module that it's on a retry run, for special cases
             such as ;) - winking emoticon - since ; is a default sentence-splitter.

=item search ($STRING)

Search all loaded replies for every trigger that C<$STRING> matches. Returns an array
of results, containing the trigger, what topic it was under, and its file and line number
where applicable.

=item write ([$FILEPATH])

Writes all the currently loaded replies into a single file. This is useful for if your
application dynamically learns replies by editing the loaded hashrefs. It will write all
replies to the file under their own topics. Comments and other unnessecary information is
ignored.

The default path is to "written.rs" in the working directory.

B<Note:> This method doesn't honor the C<%PREVIOUS> command in RiveScript.

See L<"Dynamic Replies">.

=item setGlobal (VARIABLE => VALUE, ...)

Set a global RiveScript variable directly from Perl (alias for C<! global>)

=item setVariable (VARIABLE => VALUE, ...)

Set a botvariable (alias for C<! var>)

=item setSubstitution (BEFORE => AFTER, ...)

Set a substitution setting (alias for C<! sub>)

=item setUservar ($USER_ID, VARIABLE => VALUE, ...)

Set a user variable (alias for C<E<lt>set var=valueE<gt>> for C<$USER_ID>)

=item getUservars ([$USER_ID])

Get all uservars for a user. Returns a hashref of the variables. If you don't pass in a
C<$USER_ID>, it will return a hashref of hashrefs for each user by their ID.

=back

=head2 Security Methods

The RiveScript interpreter can specify some security settings as far as what a
RiveScript file is allowed to contain.

B<Note:> These settings only apply to commands found in a RiveScript document
while it's being loaded. It does not apply to tags within RiveScript responses
(for example C<{! global ...}> could be used in a reply to reset a global variable.
This can't be helped with these commands. For ultimate security, you should have
your program manually check these things).

=over 4

=item denyMode ($MODE)

Valid modes are C<deny_some>, C<allow_some>, and C<allow_all>. allow_all is the default.
Use the C<deny()> and C<allow()> methods complementary to the denyMode specified.

=item deny (@COMMANDS)

Add C<@COMMANDS> to the denied commands list. These can be single commands or beginnings
of command texts. Example:

  $rivescript->deny (
    '&',
    '! global',
    '! var copyright',
    '> begin',
    '< begin',
    '> __begin__',
    '< __begin__',
  );

In that example, C<&PERL>, C<!GLOBAL>, the botvariable C<copyright>, and the C<BEGIN>
statements (and its internal names) are all blocked from being accepted in any loaded
RiveScript file.

=item allow (@COMMANDS)

Add C<@COMMANDS> to the allowed commands list. For the highest security, it would be better
to C<allow_some> commands rather than C<deny_some>.

  $rivescript->allow (
    '+',
    '-',
    '! var',
    '@',
  );

That example would deny every command I<except> for triggers, responses, botvariable
setters, and redirections.

=back

=head2 Private Methods

These methods are called on internally and should not be called by you.

=over 4

=item debug ($MESSAGE)

Print a debug message (when debug mode is active).

=item makeParser

Creates a L<RiveScript::Parser|RiveScript::Parser> instance, passing in the current data
held by C<RiveScript>. This call is made before using the parser (to read or write replies)
and destroyed when no longer needed.

=item intReply ($USER_ID, $MESSAGE)

This is the internal reply-getting routine. Call C<reply()> instead. This assumes that the
data is all correctly formatted before being processed.

=item splitSentences ($STRING)

Splits C<$STRING> at hte sentence-splitters and returns an array.

=item formatMessage ($STRING)

Formats C<$STRING> by running substitutions and removing punctuation and symbols.

=item mergeWildcards ($STRING, @STARS)

Merges the values from C<@STARS> into C<$STRING>, where the items in C<@STARS> correspond
to a captured value from C<$1> to C<$100+>. The first item in the array should be blank as
there is no C<E<lt>star0E<gt>>.

=item stringUtil ($TYPE, $STRING)

Formats C<$STRING> by C<$TYPE> (uppercase, lowercase, formal, sentence).

=item tagFilter ($REPLY, $ID, $MESSAGE)

Run tag filters on C<$REPLY>. Returns the new C<$REPLY>.

=item tagShortcuts ($REPLY)

Runs shortcut tags on C<$REPLY>. Returns the new C<$REPLY>.

=back

=head1 RIVESCRIPT

The following is the RiveScript 1.00 specification.

=head2 RiveScript Format

RiveScript is a line-by-line command-driven language. The first symbol(s) of each line is
a B<command>, and the following text is its B<data>.

In its most simple form, a valid RiveScript reply looks like this:

  + hello bot
  - Hello human.

=head2 RiveScript Commands

=over 4

=item B<! (Definition)>

The C<!> command is for definitions. These are used to define variables and arrays at load
time. Their format is as follows:

  ! $type $variable = $value

The supported types are as follows:

  global  - Global settings (eg. debug and sentence_splitters)
  var     - BotVariables (eg. the bot's name, age, etc)
  array   - An array
  sub     - A substitution pattern
  person  - A "person" substitution pattern
  addpath - Add an include path for RiveScript includibles
  include - Include a separate RiveScript library or package
  syslib  - Include a Perl module into the RiveScript:: namespace.

Some examples:

  // Set global variables (defaults)
  ! global debug = 0
  ! global split_sentences = 1
  ! global sentence_splitters = . ! ; ?

  // Setup a handler string for object failures.
  ! global macro_failure = <b>ERROR: Macro Failure</b>

  // Set bot vars
  ! var name   = Casey Rive
  ! var age    = 14
  ! var gender = male
  ! var color  = blue

  // Delete botvar "color"
  ! var color = undef

  // An array of color names
  ! array colors = red blue green yellow cyan fuchsia

  // An array of "can not" variations
  ! array not = can not|would not|should not|could not

  // A few substitutions
  ! sub can't = can not
  ! sub i'm   = i am

  // Person substitutions (swaps 1st- and 2nd-person pronouns)
  ! person i   = you
  ! person you = me
  ! person am  = are
  ! person are = am

  // Add a path to find libraries.
  ! addpath C:/MyRsLibraries

  // Include some English verb arrays
  ! include English/EngVerbs.rsl

  // Include a package of objects.
  ! include DateTime.rsp

B<Note:> For arrays with single-word items, separate entries with white spaces. For
multi-word items, use pipe symbols.

B<Note:> To delete a variable, set its value to "undef"

See also: L<"Environment Variables"> and L<"Person Substitution">.

=item B<E<lt> and E<gt> (Label)>

The C<E<lt>> and C<E<gt>> commands are for defining labels. A label is used to treat
a part of code differently. Currently there are three uses for labels: C<begin>, C<topic>,
and C<object>. Example:

  + you are stupid
  - You're mean. Apologize or I'm not talking to you again.{topic=apology}

  > topic apology

    + *
    - No, apologize for being so mean to me.

    + sorry
    - See, that wasn't too hard. I'll forgive you.{topic=random}

  < topic

=item B<+ (Trigger)>

The C<+> command is the basis for all reply sets. The C<+> command is what the user has
to say to activate the reply set. In the example,

  + hello bot
  - Hello human.

The user would say "hello bot" and get a "Hello human." reply.

Triggers are passed through the regexp engine. They should be completely lowercase and
not contain too many foreign characters (use substitutions to format the message any way
you want so you don't need to use foreign characters!)

=item B<% (Previous)>

The C<%> command is for drawing a user back to complete a thought. It's similar to the
C<E<lt>thatE<gt>> functionality in AIML.

  + ask me a question
  - Do you have any pets?

  + yes
  % do you have any pets
  - What kind of pet?

The C<%> command is like the C<+Trigger>, but for the bot's last reply. The same
substitutions are run on the bot's last reply as are run on the user's messages.

  ! sub who's = who is

  + knock knock
  - Who's there?

  + *
  % who is *
  - <formal> who?

  + *
  % * who
  - Haha! <sentence>! That's hilarious!

(see L<"Tags"> for details on what C<E<lt>formalE<gt>> and C<E<lt>sentenceE<gt>> are)

=item B<- (Response)>

The C<-> command is the response to a trigger. The C<-> command has several different
uses, depending on its context. One C<+Trigger> with one C<-Response> makes a one-way
question-and-answer scenario. When multiple C<-Response>s are used, they become random
replies. For more information, see L<"Complexities of the Response">.

=item B<^ (Continue)>

The C<^> command is to extend the data of the previous command. This is for editor-side
use only and has no effect on the brain when replies have all been loaded.

The following commands can be used with the C<^Continue> command:

  ! global
  ! var
  ! array
  + trigger
  % previous
  - response
  @ redirection

Here's an example of extending a very long C<-Response> over multiple lines. When the
brain is tested, the reply will come out as one long string. The C<^Continue> is only
for you, the reply writer, to make it easier to read the code.

  + tell me a poem
  - Little Miss Muffit sat on her tuffet\s
  ^ in a nonchalant sort of way.\s
  ^ With her forcefield around her,\s
  ^ the Spider, the bounder,\s
  ^ is not in the picture today.

Note that spaces are NOT assumed between
breaks. You'll need the C<\s> tag (see L<"Tags">).

=item B<@ (Redirect)>

The C<@> command is for directing one trigger to another. For example:

  + my name is *
  - Nice to meet you, <formal>.

  + people call me *
  @ my name is <star>

  + i am named *
  @ my name is <star>

=item B<* (Condition)>

The C<*> command is for checking conditions. The format is:

  * variable = value => say this

For an example, you can differentiate between male and female users:

  + am i a boy or a girl
  * gender = male   => You're a boy.
  * gender = female => You're a girl.
  - You've never told me what you are.

You can perform the following operations on variable checks:

  =  equal to
  != not equal to
  <  less than
  <= less than or equal to
  >  greater than
  >= greater than or equal to
  ?  returns true if the variable is defined

If you want to check the condition of a bot variable, prepend a C<#> sign to the variable
name. This isn't necessary, but if the user has a variable by the same name, the user's
variable overrides the bot's.

  + is your name still soandso
  * #name = Soandso => That's still my name.
  - No, I changed it.

Here's an example of the "defined" condition:

  // Only use the user's name if they've defined it to us
  + hello bot
  * name ? => Hello there, <get name>, nice to see you again!
  - Hello there!

=item B<& (Perl)>

The C<&> command is for executing Perl codes directly from a RiveScript reply set. Use this
only as a last resort, though. RiveScript is powerful enough to handle almost anything you could
want it to, and it can handle these things more securely than this command would, as this command
simply C<eval>s the expression.

  + what is 2 plus 2
  - 500 Internal Error (the eval failed for some reason!)
  & $reply = '2 + 2 = 4';

=item B<// I<or> # (Comments)>

The comment syntax is C<//>, as it is in other scripting languages. Also, C</* */> comments
can be used to span across multiple lines:

  // A one-line comment

  /*
    this comment spans
    across multiple lines
  */

Commands can be used in-line next to RiveScript commands. They need to have at least one
white space before and after the comment symbols.

  + what color is my (@colors) * // "What color is my green shoe?"
  - Your <star2> is <star1>!     // "Your shoe is green!"

The Perl comment symbol, C<#>, can be used in RiveScript as well. It follows the same
principals as the C<//> commands, but it can B<not> span across multiple lines.

=back

=head2 RiveScript Holds The Keys

The RiveScript engine was designed for the RiveScript brain to hold most of the control. As
little programming as possible on the Perl side as possible has made it so that your RiveScript
can define its own variables and handle what it wants to. See L<"A Good Brain"> for tips on how
to approach this.

=head2 Complexities of the Trigger

The C<+Trigger> can be used for more complex things than just simple, 100% dead-on triggers.
This part is passed through a regexp, hence any regexp commands can be used in the trigger...
however, don't think too much into it, you can get impressive results with simple-looking
patterns.

B<Note:> An asterisk C<*> is always converted into C<(.*?)> regardless of its context. Keep
this in mind.

=over 4

=item B<Wildcards:>

You can write open-ended triggers (called "wildcard triggers"). You can
capture the output of them, in order, by using the tags C<E<lt>star1E<gt>> to
C<E<lt>star100E<gt>>+. Example:

  + my name is *
  - Nice to meet you, <star1>.

=item B<Alternations:>

You can use alternations in the triggers like so:

  + what (s|is) your (home|office|cell) phone number

The values the user chose for each set of alternations are also put into the
C<E<lt>starE<gt>> tags like the wildcards are.

=item B<Optionals:>

You can use optional words in a trigger. These words don't have to exist in the user's message
in order to match it, but they can be. Example:

  + what is your [home] phone number
  - You can call me at 555-5555.

Alternations can be used inside of optionals as well:

  + what (s|is) your [home|office|cell] phone number

=item B<Arrays:>

This is why it's good to define arrays. Arrays can be used in any number of triggers. Here's
an example of how it works:

  // Make an array of color names
  ! array colors = red blue green yellow cyan fuchsia

  // Now they can tell us their favorite color!
  + my favorite color is (@colors)
  - Really?! Mine is <star> too!

If you want the array choice to be put into a C<E<lt>starE<gt>> tag, enclose it in parenthesis.
Without the parenthesis, it will be skipped over and not matchible. Example:

  // If the input is "sometimes I am a tool"...

  ! array be = am are is was were

  + * i @be *
    // <star1> = 'sometimes'
    // <star2> = 'tool'

  + * i (@be) *
    // <star1> = 'sometimes'
    // <star2> = 'am'
    // <star3> = 'a tool'

=back

=head2 Complexities of the Response

The C<-Response> command has many uses depending on its context:

=over 4

=item B<One-way question/answer:>

A single C<+> and a single C<-> will lead to a one-way question/answer scenario.

=item B<Random Replies:>

A single C<+> with multiple C<->'s will yield random results from the responses.

  + hello
  - Hey.
  - Hi.
  - Hello.

=item B<Fallbacks:>

When using conditionals and Perl codes, you should have at least one C<-Response>
to fall back on in case everything returns false.

=item B<Weighted Responses:>

With random replies, you can apply weight to them to improve their probability of
being chosen. All replies have a default weight of 1, and anything lower than 1 can
not be used. Example:

  + hello
  - Hello, how are you?{weight=49}
  - Yo, wazzup dawg?{weight=1}

See L<"Tags">.

=back

=head2 Begin Statement

B<The BEGIN file is the first reply file loaded in a loadDirectory call.> If a
"begin.rs" file exists in the directory being loaded, it is included first. This is
the best place to put your definitions and include statements.

B<Note:> BEGIN statements are not required.

B<How to define a BEGIN statement>

  > begin
    + request
    - {ok}
  < begin

BEGIN statements are like topics, but are always called first on every reply. If the
response contains C<{ok}> in it, then the module gets an actual reply to your message
and substitutes it for C<{ok}>. In this way, the BEGIN statement could format all the
replies in the same way. For an example:

  > begin

    // Don't give a reply if the bot is down for maintenance. Else, sentence-case
    // every reply the bot gives.
    + request
    * #maintenance = yes => Sorry, the bot is currently deactivated!
    - {sentence}{ok}{/sentence}

  < begin

Here is a more complex example using a botvariable "mood"

  > begin
    + request
    * mood = happy  => {ok}
    * mood = sad    => {lowercase}{ok}{/lowercase}
    * mood = angry  => {uppercase}{ok}{/uppercase}
    * mood = pissed => {@not talking}
    - {ok}

    + not talking
    - I'm not in a talkative mood.
    - I don't want to talk right now.
  < begin

B<Note:> The only trigger that BEGIN receives automatically is C<request>.

=head2 Topics

Topics are declared in a similar way to the BEGIN statement. To declare and close a topic,
the syntax is as follows:

  > topic NAME
    ...
  < topic

The topic name should be unique and only one word.

B<The Default Topic:> The default topic name is "C<random>"

B<Setting a Topic:> To set a topic, use the C<{topic}> tag (see L<"Tags"> below).

  + you are stupid
  - You're mean. Apologize or I'm not talking to you again.{topic=apology}

  > topic apology

    + *
    - No, apologize for being so mean to me.

    + sorry
    - See, that wasn't too hard. I'll forgive you.{topic=random}

  < topic

Always set topic back to "random" to break out of a topic.

=head2 Object Macros

Special macros (Perl routines) can be defined and then utilized in your RiveScript code.

=over 4

=item B<Inline Objects>

You can define objects within your RiveScript code. When doing this, keep in mind that the
object is included as part of the C<RiveScript::> namespace. That being said, here are some
basic tips to follow:

  1) If it uses any modules, they need to be explicitely declared with a 'use' statement.
  2) If it refers to any variables global to your main script, 'main::' must be prepended.
     Example: '$main::hashref->{key}'
  3) If it refers to any subroutine of your main program, 'main::' must be prepended.
     Example: '&main::reload()'

Here's a full example of an object:

  + give me a fortune cookie
  - Your random fortune cookie: &fortune.get()

  > object fortune
    my ($method,$msg) = @_;

    my @cookies = (
      'You will be rich and famous',
      'You will meet a celebrity',
      'You will go to the moon',
    );

    return $cookies [ int(rand(scalar(@cookies))) ];
  < object

=item B<Define an Object from Perl>

This is done like so:

  # Define a weather lookup macro.
  $rivescript->setSubroutine (weather => \&weather_lookup);

=item B<Call an Object>

To call on an object inside of a reply, the format is:

  &object_name.method_name(argument)

All objects receive C<$method> (the data after the dot) and C<$argument> (the data inside
the parenthesis). Here's another example:

  + encode * in base64
  - &encode.base64(<star>)

  + encode * in md5
  - &encode.md5(<star>)

  > object encode
    my ($method,$data) = @_;

    use MIME::Base64 qw(encode_base64);
    use Digest::MD5 qw(md5_hex);

    if ($method eq 'base64') {
      return encode_base64 ($data);
    }
    else {
      return md5_hex ($data);
    }
  < object

B<Note:> If an object does not exist, has faulty code, or does not return a reply, the contents
of global C<macro_failure> will be inserted instead. The module cannot tell you which of the
three errors is the cause, though.

=back

=head2 Tags

Special tags can be inserted into RiveScript replies. The tags are as follows:

=over 4

=item B<E<lt>starE<gt>, E<lt>star1E<gt> - E<lt>star100E<gt>+>

These tags will insert the values of C<$1> to C<$100>+, as matched in the trigger regexp.
C<E<lt>starE<gt>> is an alias for C<E<lt>star1E<gt>>.

=item B<E<lt>input1E<gt> - E<lt>input9E<gt>, E<lt>reply1E<gt> - E<lt>reply9E<gt>>

Inserts the last 1 to 9 things the user said, and the last 1 to 9 things the bot replied
with, respectively.

=item B<E<id>>

Inserts the user's ID.

=item B<E<bot>>

Insert a bot variable (defined with C<! var>).

  + what is your name
  - I am <bot name>, created by <bot author>.

This is also the only tag that can be used in triggers.

  + my name is <bot name>
  - <set name=<bot name>>What a coincidence, that's my name too!

=item B<E<lt>getE<gt>, E<lt>setE<gt>>

Get and set a user variable. These are local variables for the current user.

  + my name is *
  - <set name=<formal>>Nice to meet you, <get name>!

  + who am i
  - You are <get name> aren't you?

=item B<E<lt>addE<gt>, E<lt>subE<gt>, E<lt>multE<gt>, E<lt>divE<gt>>

Add, subtract, multiple and divide numeric variables, respectively.

  + give me 5 points
  - <add points=5>You have receive 5 points and now have <get points> total.

If the variable is undefined, it is set to 0 before the math is done on it. If you try
to modify a defined, but not numeric, variable (such as "name") then B<(Var=NaN)> is
inserted in place of this tag.

Likewise, if you modify a variable with a non-numeric value, then B<(Value=NaN)> is
inserted.

=item B<{topic=...}>

This will change the user's topic. See L<"Topics">.

=item B<{nextreply}>

Breaks the reply into two parts here. This will cause C<reply()> to return multiple
responses for each side of the C<{nextreply}> tag.

=item B<{weight=...}>

Add some weight to a C<-Response>. See L<"Complexities of the Response">.

=item B<{@...}, E<lt>@E<gt>>

An inline redirection. These work like normal redirections but can be inserted into another
reply.

  + * or something
  - Or something. {@<star>}

C<E<lt>@E<gt>> is an alias for C<{@E<lt>starE<gt>}>

=item B<{!...}>

An inline definition.

=item B<{random}...{/random}>

Inserts a random bit of text. Separate single-word items with spaces or multi-word items
with pipes.

  + test random
  - This {random}reply response{/random} has random {random}bits of text|pieces of data{/random}.

=item B<{person}...{/person}, E<lt>personE<gt>>

Will take the enclosed text and run person substitutions on them. See L<"Person Substitution">.

C<E<lt>personE<gt>> is an alias for C<{person}E<lt>starE<gt>{/person}>

=item B<{formal}...{/formal}, E<lt>formalE<gt>>

Will Make Your Text Formal.

C<E<lt>formalE<gt>> is an alias for C<{formal}E<lt>starE<gt>{/formal}>

=item B<{sentence}...{/sentence}, E<lt>sentenceE<gt>>

Will make your text sentence-cased.

C<E<lt>sentenceE<gt>> is an alias for C<{sentence}E<lt>starE<gt>{/sentence}>

=item B<{uppercase}...{/uppercase}, E<lt>uppercaseE<gt>>

WILL MAKE THE TEXT UPPERCASE.

C<E<lt>uppercaseE<gt>> is an alias for C<{uppercase}E<lt>starE<gt>{/uppercase}>

=item B<{lowercase}...{/lowercase}, E<lt>lowercaseE<gt>>

will make the text lowercase.

C<E<lt>lowercaseE<gt>> is an alias for C<{lowercase}E<lt>starE<gt>{/lowercase}>

=item B<{ok}>

This is used only with the L<"Begin Statement">. It tells the interpreter that it's okay to
get a reply.

=item B<\s>

Inserts a white space.

=item B<\n>

Inserts a newline.

=item B<\/>

Insert a forward slash. This is to include forward slashes without them being interpreted
as comments.

=item B<\#>

Inserts a pound symbol. This is to include pound symbols without them being interpreted
as comments.

=back

=head2 Environment Variables

Environment variables are kept as "botvariables" and can be retrieved with the
C<E<lt>botE<gt>> tags. The variable names are all uppercase and begin with "ENV_"

=over 4

=item B<RiveScript Environment Variables>

  ENV_OS          = The operating system RiveScript is running on.
  ENV_APPVERSION  = The version of RiveScript being used.
  ENV_APPNAME     = A user-agent style string ("RiveScript/1.00")
  ENV_REPLY_COUNT = The number of loaded triggers.

=item B<Perl Environment Variables>

All Perl variables are prepended with "ENV_SYS_", so that "ENV_SYS_REMOTE_ADDR" would
contain the user's IP address if RiveScript was used via HTTP CGI.

=item B<Setting Environment Variables>

RiveScript's syntax prohibits the modification of environment variables through any
loaded RiveScript document. However, you can call the method C<setVariable()> to
change environment variables from the Perl side if need-be.

=back

=head2 Person Substitution

The C<{person}> tag can be used to perform substitutions between 1st- and 2nd-person
pronouns.

You can define these with the C<!define> tag:

  ! person i     = you
  ! person my    = your
  ! person mine  = yours
  ! person me    = you
  ! person am    = are
  ! person you   = I
  ! person your  = my
  ! person yours = mine
  ! person are   = am

Then use the C<{person}> tag in a response. The enclosed text will swap these pronouns.

  + do you think *
  - What if I do think {person}<star>{/person}?

  "Do you think I am a bad person?"
  "What if I do think you are a bad person?"

Without the person tags, it would say "What if I do think I am a bad person?" and not make very
much sense.

B<Note:> RiveScript does not assume any pre-set substitutions. You must define them in your own
brains.

=head2 Dynamic Replies

Here is an overview of the internal hashref structure of the RiveScript object, for modifying
replies directly.

=over 4

=item B<$rs-E<gt>{replies}>

This hashref contains all of the replies. The first keys are the topic name, then the trigger
texts under that topic.

So, B<$rs-E<gt>{replies}-E<gt>{random}> contains all triggers for the default topic.

B<$rs->{replies}->{random}->{'my favorite color is (@colors) *'}> would be the location of a
specific trigger.

=item B<Trigger Sub-Keys>

The following keys are underneath a trigger key (B<$rs->{replies}->{$topic}->{$trigger}>)

B<1..n> - The C<-Responses> under the trigger, in order.

B<redirect> - The contents of the C<@Redirect> if applicable.

B<conditions->{1..n}> - The data from the C<*Condition> commands, in order.

B<system->{codes}> - The contents of any C<&Perl> codes if applicable.

=item B<Examples>

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

=back

=head2 Included Files

B<Recommended practice> is to place all your C<!include> statements inside your begin.rs file,
as this file is always loaded in first.

=over 4

=item B<RiveScript Libraries>

RiveScript Libraries (B<.rsl> extension) are special RiveScript documents that are generally
full of arrays and substitutions. For instance, the RiveScript distribution comes with English.rsl
which is full of English nouns, verbs, and adjectives.

=item B<RiveScript Packages>

RiveScript Packages (B<.rsp> extension) are special RiveScript documents that are generally
full of objects. The RiveScript distribution comes with DateTime.rsp, which has an object for
returning time stamps.

=item B<RiveScript Include Search Path>

The default RiveScript Includes search path is the array of Perl's C<@INC>, with "/RiveScript"
tacked on to the end of it. Also, the working directory of your script is included in this.

You can use the C<!addpath> directive to add new search paths.

=back

=head2 Reserved Variables

The following are all the reserved variables within RiveScript which cannot be (re)set by
your reply files.

=over 4

=item B<Reserved Global Variables>

These variables can't be overwritten with the C<!global> command:

  reserved replies array syntax streamcache botvars uservars
  botarrays sort users substitutions

=item B<Reserved Topic Names>

The following topic names are special and should never be (re)created in your RiveScript files.

  __begin__  (used for the BEGIN statement)
  __that__*  (used for the %Previous command)

=back

=head2 A Good Brain

Since RiveScript leaves a lot of control up to the brain and not the Perl code, here are some
general tips to follow when writing your own brain:

=over 4

=item B<Make a config file.>

This would probably be named "config.rs" and it would handle all
your definitions. For example it might look like this:

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

=item B<Make a begin file.>

Create a file called "begin.rs" -- there are several reasons for doing so.

For one, you should use this file for C<!include> statements if you want your brain
to use some common libraries or packages. Secondly, you can use the B<E<lt>BEGIN> statement
to setup a handler for incoming messages.

Your begin file could check the "active" variable we set in the config file to decide if it should give a reply.

  > begin
    + request
    * active=no => Sorry but I'm deactivated right now!
    - {ok}
  < begin

These are the basic tips, just for organizational purposes.

=back

=head1 SEE OTHER

L<RiveScript::Parser> - Reading and Writing of RiveScript Documents.

L<RiveScript::Brain> - The reply and search methods of RiveScript.

L<RiveScript::Util> - String utilities for RiveScript.

=head1 CHANGES

  Version 1.00
  - Public stable beta release.

  Version 0.21
  - Added \u tag for inserting an "undefined" character (i.e. set global macro_failure
    to \u to remove macro failure notifications altogether from the responses)
  - The code to run objects is now run last in RiveScript::Util::tagFilter, so that other
    tags such as {random}, <get>, etc. are all run before the object is executed.
  - Two new standard libraries have been added:
    - Colors.rsl - Arrays for color names
    - Numbers.rsl - Arrays for number names

  Version 0.20
  - Added shortcut tags: <person>, <@>, <formal>, <sentence>, <uppercase>, <lowercase>,
    for running the respective tags on <star> (i.e. <person> ==> {person}<star>{/person})
  - Added environment variable ENV_REPLY_COUNT which holds the number of loaded triggers.
  - Bugfix: sending scalar=>0 to reply() was returning the scalar of the array of replies,
    not the array itself. This has been fixed.

  Version 0.19
  - Added methods for allowing or denying certain commands to be used when RiveScript
    documents are loaded in.
  - Bugfix: the sortThats() method of RiveScript::Parser was blanking out the current
    value of $self->{thatarray} -- meaning, the last file to have %Previous commands used
    would be kept in memory, previous ones would be lost. This has been fixed now.

  Version 0.18
  - Minor bugfix with the "%PREVIOUS" internal array.

  Version 0.17
  - All the "%PREVIOUS" commands found at loading time are now sorted in an internal
    arrayref, in the same manner that "+TRIGGERS" are. This solves the bug with
    matchability when using several %PREVIOUS commands in your replies.
  - Added the # command as a "Perly" alternative to // comments.
  - Comments can be used in-line next to normal RiveScript code, requiring that at
    least one space exist before and after the comment symbols. You can escape the
    symbols too if you need them in the reply.
  - Created a new package DateTime.rsp for your timestamp-formatting needs.

  Version 0.16
  - Added "! syslib" directive for including Perl modules at the RiveScript:: level,
    to save on memory usage when more than one object might want the same module.
  - The "%PREVIOUS" directive now takes a regexp. The bot's last reply is saved as-is,
    not formatted to lowercase. The % command now works like a +Trigger for the bot's
    last reply.
  - The "%PREVIOUS" directive check has been moved to another subroutine. In this way,
    its priority is much higher. A trigger of * (catch-all) with a %PREVIOUS will always
    match, for example.
  - Fixed a bug with the BEGIN method. The bot's reply is no longer saved while the
    topic is __begin__ - this messed up the %THAT directive.

  Version 0.15
  - Broke RiveScript into multiple sub-modules.

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

=head1 SPECIAL THANKS

Special thanks goes out to B<jeffohrt> and B<harleypig> of the AiChaos Forum for
helping so much with RiveScript's development.

=head1 KEYWORDS

bot, chatbot, chatterbot, chatter bot, reply, replies, script, aiml, alpha

=head1 AUTHOR

  Cerone Kirsle, kirsle --at-- f2mb.com

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
