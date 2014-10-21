# NAME

RiveScript - Rendering Intelligence Very Easily

# SYNOPSIS

```perl
use RiveScript;

# Create a new RiveScript interpreter.
my $rs = new RiveScript;

# Load a directory of replies.
$rs->loadDirectory ("./replies");

# Load another file.
$rs->loadFile ("./more_replies.rive");

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
```

# DESCRIPTION

RiveScript is a simple trigger/response language primarily used for the creation
of chatting robots. It's designed to have an easy-to-learn syntax but provide a
lot of power and flexibility. For more information, visit
http://www.rivescript.com/

# METHODS

## GENERAL

- RiveScript new (hash %ARGS)

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
        utf8      - Enable UTF-8 support for the RiveScript code. See the section on
                    UTF-8 support for details.
        depth     - Determines the recursion depth limit when following a trail of replies
                    that point to other replies. Default is 50.
        strict    - If this has a true value, any syntax errors detected while parsing
                    a RiveScript document will result in a fatal error. Set it to a
                    false value and only a warning will result. Default is 1.

    It's recommended that if you set any other global variables that you do so by
    calling `setGlobal` or defining it within the RiveScript code. This will avoid
    the possibility of overriding reserved globals. Currently, these variable names
    are reserved:

        topics   sorted  sortsthat  sortedthat  thats
        arrays   subs    person     client      bot
        objects  syntax  sortlist   reserved    debugopts
        frozen   globals handlers   objlangs

    Note: the options "verbose" and "debugfile", when provided, are noted and then
    deleted from the root object space, so that if your RiveScript code uses variables
    by the same values it won't conflict with the values that you passed here.

## LOADING AND PARSING

- bool loadDirectory (string $PATH\[, string @EXTS\])

    Load a directory full of RiveScript documents. `$PATH` must be a path to a
    directory. `@EXTS` is optionally an array containing file extensions, including
    the dot. By default `@EXTS` is `('.rive', '.rs')`.

    Returns true on success, false on failure.

- bool loadFile (string $PATH)

    Load a single RiveScript document. `$PATH` should be the path to a valid
    RiveScript file. Returns true on success; false otherwise.

- bool stream (arrayref $CODE)

    Stream RiveScript code directly into the module. This is for providing RS code
    from within the Perl script instead of from an external file. Returns true on
    success.

- string checkSyntax (char $COMMAND, string $LINE)

    Check the syntax of a line of RiveScript code. This is called automatically
    for each line parsed by the module. `$COMMAND` is the command part of the
    line, and `$LINE` is the rest of the line following the command (and
    excluding inline comments).

    If there is no problem with the line, this method returns `undef`. Otherwise
    it returns the text of the syntax error.

    If `strict` mode is enabled in the constructor (which is on by default), a
    syntax error will result in a fatal error. If it's not enabled, the error is
    only sent via `warn` and the file currently being processed is aborted.

- void sortReplies ()

    Call this method after loading replies to create an internal sort buffer. This
    is necessary for trigger matching purposes. If you fail to call this method
    yourself, RiveScript will call it once when you request a reply. However, it
    will complain loudly about it.

- data deparse ()

    Translate the in-memory representation of the loaded RiveScript documents into
    a Perl data structure. This would be useful for developing a user interface to
    facilitate editing of RiveScript replies without having to edit the RiveScript
    code manually.

    The data structure returned from this will follow this format:

    ```perl
        {
          "begin" => { # Contains begin block and config settings
            "global" => { # ! global (global variables)
              "depth" => 50,
              ...
            },
            "var" => {    # ! var (bot variables)
              "name" => "Aiden",
              ...
            },
            "sub" => {    # ! sub (substitutions)
              "what's" => "what is",
              ...
            },
            "person" => { # ! person (person substitutions)
              "you" => "I",
              ...
            },
            "array" => {  # ! array (arrays)
              "colors" => [ "red", "green", "light green", "blue" ],
              ...
            },
            "triggers" => {  # triggers in your > begin block
              "request" => { # trigger "+ request"
                "reply" => [ "{ok}" ],
              },
            },
          },
          "topic" => { # all topics under here
            "random" => { # topic names (default is random)
              "hello bot" => { # trigger labels
                "reply"     => [ "Hello human!" ], # Array of -Replies
                "redirect"  => "hello",            # Only if @Redirect exists
                "previous"  => "hello human",      # Only if %Previous exists
                "condition" => [                   # Only if *Conditions exist
                  "<get name> != undefined => Hello <get name>!",
                  ...
                ],
              },
            },
          },
          "include" => { # topic inclusion
            "alpha" => [ "beta", "gamma" ], # > topic alpha includes beta gamma
          },
          "inherit" => { # topic inheritence
            "alpha" => [ "delta" ], # > topic alpha inherits delta
          }
        }
    ```

    Note that inline object macros can't be deparsed this way. This is probably for
    the best (for security, etc). The global variables "debug" and "depth" are only
    provided if the values differ from the defaults (true and 50, respectively).

- void write (glob $fh || string $file\[, data $deparsed\])

    Write the currently parsed RiveScript data into a RiveScript file. This uses
    `deparse()` to dump a representation of the loaded data and writes it to the
    destination file. Pass either a filehandle or a file name.

    If you provide `$deparsed`, it should be a data structure matching the format
    of `deparse()`. This way you can deparse your RiveScript brain, add/edit
    replies and then pass in the new version to this method to save the changes
    back to disk. Otherwise, `deparse()` will be called to get the current
    snapshot of the brain.

## CONFIGURATION

- bool setHandler (string $LANGUAGE => code $CODEREF, ...)

    Define some code to handle objects of a particular programming language. If the
    coderef is `undef`, it will delete the handler.

    The code receives the variables `$rs, $action, $name,` and `$data`. These
    variables are described here:

        $rs     = Reference to Perl RiveScript object.
        $action = "load" during the parsing phase when an >object is found.
                  "call" when provoked via a <call> tag for a reply
        $name   = The name of the object.
        $data   = The source of the object during the parsing phase, or an array
                  reference of arguments when provoked via a <call> tag.

    There is a default handler set up that handles Perl objects.

    If you want to block Perl objects from being loaded, you can just set it to be
    undef, and its handler will be deleted and Perl objects will be skipped over:

        $rs->setHandler (perl => undef);

    The rationale behind this "pluggable" object interface is that it makes
    RiveScript more flexible given certain environments. For instance, if you use
    RiveScript on the web where the user chats with your bot using CGI, you might
    define a handler so that JavaScript objects can be loaded and called. Perl
    itself can't execute JavaScript, but the user's web browser can.

    See the JavaScript example in the `docs` directory in this distribution.

- bool setSubroutine (string $NAME, code $CODEREF)

    Manually create a RiveScript object (a dynamic bit of Perl code that can be
    provoked in a RiveScript response). `$NAME` should be a single-word,
    alphanumeric string. `$CODEREF` should be a pointer to a subroutine or an
    anonymous sub.

- bool setGlobal (hash %DATA)

    Set one or more global variables, in hash form, where the keys are the variable
    names and the values are their value. This subroutine will make sure that you
    don't override any reserved global variables, and warn if that happens.

    This is equivalent to `! global` in RiveScript code.

    To delete a global, set its value to `undef` or "`<undef>`". This
    is true for variables, substitutions, person, and uservars.

- bool setVariable (hash %DATA)

    Set one or more bot variables (things that describe your bot's personality).

    This is equivalent to `! var` in RiveScript code.

- bool setSubstitution (hash %DATA)

    Set one or more substitution patterns. The keys should be the original word, and
    the value should be the word to substitute with it.

    ```perl
        $rs->setSubstitution (
          q{what's}  => 'what is',
          q{what're} => 'what are',
        );
    ```

    This is equivalent to `! sub` in RiveScript code.

- bool setPerson (hash %DATA)

    Set a person substitution. This is equivalent to `! person` in RiveScript code.

- bool setUservar (string $USER, hash %DATA)

    Set a variable for a user. `$USER` should be their User ID, and `%DATA` is a
    hash containing variable/value pairs.

    This is like `<set>` for a specific user.

- string getUservar (string $USER, string $VAR)

    This is an alias for getUservars, and is here because it makes more grammatical
    sense.

- data getUservars (\[string $USER\]\[, string $VAR\])

    Get all the variables about a user. If a username is provided, returns a hash
    __reference__ containing that user's information. Else, a hash reference of all
    the users and their information is returned.

    You can optionally pass a second argument, `$VAR`, to get a specific variable
    that belongs to the user. For instance, `getUservars ("soandso", "age")`.

    This is like `<get>` for a specific user or for all users.

- bool clearUservars (\[string $USER\])

    Clears all variables about `$USER`. If no `$USER` is provided, clears all
    variables about all users.

- bool freezeUservars (string $USER)

    Freeze the current state of variables for user `$USER`. This will back up the
    user's current state (their variables and reply history). This won't statically
    prevent the user's state from changing; it merely saves its current state. Then
    use thawUservars() to revert back to this previous state.

- bool thawUservars (string $USER\[, hash %OPTIONS\])

    If the variables for `$USER` were previously frozen, this method will restore
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

    ```perl
        # Delete the frozen cache but don't modify the user's variables.
        $rs->thawUservars ("soandso", discard => 1);

        # Restore the user's state from cache, but don't delete the cache.
        $rs->thawUservars ("soandso", keep => 1);
    ```

- string lastMatch (string $USER)

    After fetching a reply for user `$USER`, the `lastMatch` method will return the
    raw text of the trigger that the user has matched with their reply. This function
    may return undef in the event that the user __did not__ match any trigger at all
    (likely the last reply was "`ERR: No Reply Matched`" as well).

- string currentUser ()

    Get the user ID of the current user chatting with the bot. This is mostly useful
    inside of a Perl object macro in RiveScript to get the user ID of the person who
    invoked the object macro (e.g., to get/set variables for them using the
    `$rs` instance).

    This will return `undef` if used outside the context of a reply (the value is
    unset at the end of the `reply()` method).

## INTERACTION

- string reply (string $USER, string $MESSAGE)

    Fetch a response to `$MESSAGE` from user `$USER`. RiveScript will take care of
    lowercasing, running substitutions, and removing punctuation from the message.

    Returns a response from the RiveScript brain.

# RIVESCRIPT

This interpreter tries its best to follow RiveScript standards. Currently it
supports RiveScript 2.0 documents. A current copy of the RiveScript working
draft is included with this package: see [RiveScript::WD](http://search.cpan.org/perldoc?RiveScript::WD).

# UTF-8 SUPPORT

Version 1.29+ adds experimental support for UTF-8 in RiveScript. It is not
enabled by default. Enable it by passing a true value for the `utf8` option
in the constructor, or by using the `--utf8` argument to the `rivescript`
application.

By default (without UTF-8 mode on), triggers may only contain basic ASCII
characters (no foreign characters), and the user's message is stripped of
all characters except letters and spaces. This means that, for example, you
can't capture a user's e-mail address in a RiveScript reply, because of the
@ and . characters.

When UTF-8 mode is enabled, these restrictions are lifted. Triggers are only
limited to not contain certain metacharacters like the backslash, and the
user's message is only stripped of backslashes and HTML angled brackets (to
prevent obvious XSS if you use RiveScript in a web application). The
`<star>` tags in RiveScript will capture the user's "raw" input,
so you can write replies to get the user's e-mail address or store foreign
characters in their name.

# CONSTANTS

This module can export some constants.

    use RiveScript qw(:standard);

These constants include:

- RS\_ERR\_MATCH

    This is the reply text given when no trigger has matched the message. It equals
    "`ERR: No Reply Matched`".

    ```perl
        if ($reply eq RS_ERR_MATCH) {
          $reply = "I couldn't find a good reply for you!";
        }
    ```

- RS\_ERR\_REPLY

    This is the reply text given when a trigger _was_ matched, but no reply was
    given from it (for example, the trigger only had conditionals and all of them
    were false, with no default replies to fall back on). It equals
    "`ERR: No Reply Found`".

    ```perl
        if ($reply eq RS_ERR_REPLY) {
          $reply = "I don't know what to say about that!";
        }
    ```

# SEE ALSO

[RiveScript::WD](http://search.cpan.org/perldoc?RiveScript::WD) - A current snapshot of the Working Draft that
defines the standards of RiveScript.

[http://www.rivescript.com/](http://www.rivescript.com/) - The official homepage of RiveScript.

# CHANGES

    1.34  Feb 26 2014
    - Update README.md to include module documentation for github.
    - Fixes to META.yml

    1.32  Feb 24 2014
    - Maintenance release to fix some errors per the CPANTS.
    - Add license to Makefile.PL
    - Make Makefile.PL not executable
    - Make version numbers consistent

    1.30  Nov 25 2013
    - Added "TCP Mode" to the `rivescript` command so that it can listen on a
      socket instead of using standard input and output.
    - Added a "--data" option to the `rivescript` command for providing JSON
      input as a command line argument instead of standard input.
    - Added experimental UTF-8 support.
    - Bugfix: don't use hacky ROT13-encoded placeholders for message
      substitutions... use a null character method instead. ;)
    - Make .rive the default preferred file extension for RiveScript documents
      instead of .rs (which conflicts with the Rust programming language).
      Backwards compatibility remains to load .rs files, though.

    1.28  Aug 14 2012
    - FIXED: Typos in RiveScript::WD (Bug #77618)
    - Added constants RS_ERR_MATCH and RS_ERR_REPLY.

    1.26  May 29 2012
    - Added EXE_FILES to Makefile.PL so the rivescript utility installs
      correctly.

    1.24  May 15 2012
    - Fixed: having a single-line, multiline comment, e.g. /* ... */
    - Fixed: you can use <input> and <reply> in triggers now, instead of only
      <input1>-<input9> and <reply1>-<reply9>
    - When a trigger consists of nothing but multiple wildcard symbols, sort
      the trigger by length, this way you can have '* * * * *' type triggers
      still work correctly (each <star> tag would get one word, with the final
      <star> collecting the remainder).
    - Backported new feature from Python lib: you can now use <bot> and <env>
      to SET variables (eg. <bot mood=happy>). The {!...} tag is deprecated.
    - New feature: deparse() will return a Perl data structure representing all
      of the RiveScript code parsed by the module so far. This way you can build
      a user interface for editing replies without requiring a user to edit the
      code directly.
    - New method: write() will use deparse() to write a RiveScript document using
      all of the in-memory triggers/responses/etc.
    - Cleaned up the POD documentation, put POD code along side the Perl functions
      it documents, removed useless bloat from the docs.
    - POD documentation now only shows recent changes. For older changes, see the
      "CHANGES" file in the distribution.
    - Removed the `rsup` script from the distribution (it upgrades RiveScript 1.x
      code to 2.x; there probably isn't any 1.x code out in the wild anyway).

    1.22  Sep 22 2011
    - Cleaned up the documentation of RiveScript; moved the JavaScript object
      example to a separate document in the `docs' directory.
    - Obsoleted the `rsdemo` command that used to ship with the distribution. In
      its place is `rivescript`, which can also be used non-interactively so that a
      third party, non-Perl application could still make use of RiveScript.
    - RiveScript.pm is now dual licensed. It uses the GPLv2 for open source
      applications as before, but you can contact the author for details if you
      want to use RiveScript.pm in a closed source commercial application.

    1.20  Jul 30 2009
    - Added automatic syntax checking when parsing RiveScript code. Also added
      'strict mode' - if true (default), a syntax error is a fatal error. If false,
      a syntax error is a warning, and RiveScript aborts processing the file any
      further.
    - Changed the behavior of "inherits" a bit: a new type has been added called
      "includes" which does what the old "inherits" does (mixes the trigger list
      of both topics together into the same pool). The new "inherits" option though
      causes the trigger list from the source topic to be higher in matching priority
      than the trigger list of the inherited topic.
    - Moving to a new versioning scheme: development releases will have odd
      version numbers, stable (CPAN) versions will have even numbers.
    - Fixed the Eliza brain; in many places a <star2> was used when there was only one
      star in the trigger. Fixes lots of issues with Eliza.
    - Bugfix: recursion depth limits weren't taken into account when the {@} tag
      was responsible for a redirection. Fixed.
    - Bugfix: there was a problem in the regular expression that counts real words
      while sorting triggers, so that triggers with *'s in them weren't sorted
      properly and would therefore cause matching issues.
    - Bugfix: when the internal _getreply is called because of a recursive
      redirection (@, {@}), the %previous tags should be ignored. They weren't.
      since "lastreply" is always the same no matter how deeply recursive _getreply
      is going, it could result in some infinite recursion in rare cases. Fixed.
    - Bugfix: using a reserved name as a global variable wasn't working properly
      and would crash RiveScript. Fixed.

    1.19  Apr 12 2009
    - Added support for defining custom object handlers for non-Perl programming
      languages.
    - All the methods like setGlobal, setVariable, setUservar, etc. will now
      accept undef or "<undef>" as values - this will delete the variables.
    - There are no reserved global variable names anymore. Now, if a variable name
      would conflict with a reserved name, it is put into a "protected" space
      elsewhere in the object. Still take note of which names are reserved though.

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

# AUTHOR

    Noah Petherbridge, http://www.kirsle.net

# KEYWORDS

bot, chatbot, chatterbot, chatter bot, reply, replies, script, aiml, alpha

# COPYRIGHT AND LICENSE

The Perl RiveScript interpreter is dual licensed as of version 1.22.
For open source applications the module is using the GNU General Public
License. If you'd like to use the RiveScript module in a closed source or
commercial application, contact the author for more information.

    RiveScript - Rendering Intelligence Very Easily
    Copyright (C) 2014 Noah Petherbridge

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
