/*
	RiveScript // Testing the various commands

	You might recognize this type of reply set from
	Chatbot::Alpha's day.
*/

/* ##############################
   ## Simple Reply Testing     ##
   ############################## */

+ test single
- This is a single reply.

+ test random
- This is random reply #1.
- This is the second random reply.
- Here is random reply #3.

/* ##############################
   ## Variables Testing        ##
   ############################## */

+ test variables
- My name is {^name}. I am {^age} years old.

// Test setting and getting a user variable
+ set name to *
- <set name={formal}<star1>{/formal}>Your name has been set to <get name>.

+ get name
- Your name is <get name>.

// Print all uservars to DOS window.
+ show vars
- Showing variables... &uservars.show()

/* ##############################
   ## Test Conditionals        ##
   ############################## */

+ is your name bob or casey
* #name=Bob => I'm Bob.
* #name=Casey Rive => I'm Casey.
- Neither of those are my name.

+ is my name bob
* name =  Bob => Yes, that's your name. (<get name>; <bot name>)
* name != Bob => It most certainly is not!
- No, it's not.

+ test lt name
* name < Bob => This shouldn't be called, Bob isn't numeric.
- The test must have passed.

+ are you a guy or a girl
* sex=male => I'm a guy.
* sex=female => I'm a girl.
- That has yet to be determined.

/* ##############################
   ## Test Global Var Setting  ##
   ############################## */

+ test set name to bob
- {!var name = Bob}I set my name to Bob.

+ test set name to casey
- {!var name = Casey Rive}I set my name to Casey Rive.

+ test set debug on
- {!global debug = 1}Debug mode on.

+ test set debug off
- {!global debug = undef}Debug mode deactivated.

/* ##############################
   ## Test Object Macros       ##
   ############################## */

+ test object get
- Testing "get" method: &test.get()

+ test object say *
- Testing "say" method: &test.say(<star1>)

+ test object no args
- Testing object with no args: &test()

+ test void object
- Testing a void object: &void.test()

/* ##############################
   ## Wildcards Testing        ##
   ############################## */

+ test my name is *
- Nice to meet you, {formal}<star1>{/formal}.

+ * told me to say *
- Why would {formal}<star1>{/formal} tell you to say that?

/* ##############################
   ## Substitutions Testing    ##
   ############################## */

// say "I'm testing subs"
+ i am testing subs
- Did the substitution testing pass?

/* ##############################
   ## Inline Redirect Tests    ##
   ############################## */

+ test inline redirect
- If you said hello I would've said: {@hello} But if you said bye I'd say: {@bye}

+ i say *
- Indeed you do say. {@<star1>}

/* ##############################
   ## String Modify Testing    ##
   ############################## */

+ test formal odd
- {formal}this... is a test/of using odd\characters with formal.{/formal}

+ test sentence odd
- {sentence}this=/\is a test--of using odd@characters in sentence.{/sentence}

+ test uppercase
- {uppercase}this response really was lowercased at one point.{/uppercase}

+ test lowercase
- {lowercase}ThiS ORIgINal SENTence HaD CraZY CaPS iN IT!{/lowercase}

/* ##############################
   ## Long Reply Test          ##
   ############################## */

+ tell me a poem
- Little Miss Muffet,\n
^ sat on her tuffet,\n
^ in a nonchalant sort of way.\n\n
^ With her forcefield around her,\n
^ the spider, the bounder\n
^ is not in the picture today.

/* ##############################
   ## Deep Recursion Test      ##
   ############################## */

+ test recurse
@ do recurse testing

+ do recurse testing
@ test recurse

/* ##############################
   ## Test "previous"          ##
   ############################## */

+ i hate you
- You're really mean.

+ sorry
% youre really mean
- Don't worry--it's okay. ;-)

// This one stands alone.
+ sorry
- Why are you sorry?

/* ##############################
   ## Strong Redirect Test     ##
   ############################## */

+ identify yourself
- I am the RiveScript test brain.

+ who are you
@ identify yourself

/* ##############################
   ## Perl Evaluation Test     ##
   ############################## */

+ what is 2 plus 2
- 500 Internal Error.
& $reply = "2 + 2 = 4";

/* ##############################
   ## Alternation Tests        ##
   ############################## */

+ i (should|should not) do it
- You <star1> do it?

+ what (s|is) your (home|cell|work) phone number
- 555-555-5555

/* ##############################
   ## Randomness Tests         ##
   ############################## */

+ random test one
- This {random}reply trigger command{/random} has a random noun.

+ random test two
- Fortune Cookie: {random}You will be rich and famous.|You will
^ go to the moon.|You will suffer an agonizing death.{/random}

/* ##############################
   ## Test Nextreply           ##
   ############################## */

+ test nextreply
- This reply should{nextreply}appear very big{nextreply}and need 3 replies!

/* ##############################
   ## Test Input-Arrays        ##
   ############################## */

+ what color is my @colors *
- Your <star2> is <star1>, silly!

+ i * the color (?:@colors)
- I like it too. (star = <star>; 2 = <star2>)

/* ##############################
   ## Follow-up on ^ var conc. ##
   ############################## */

+ what is your favorite quote
- "<bot quote>"

/* ##############################
   ## Test trigger conc.       ##
   ############################## */

+ how much wood would a woodchuck\s
^ chuck if a woodchuck could chuck wood
- A whole forest. ;)

+ how much wood
@ how much wood would a woodchuck\s
^ chuck if a woodchuck could chuck wood

/* ##############################
   ## Test Topics              ##
   ############################## */

+ you suck
- And you're very rude. Apologize to me now!{topic=apology}

> topic apology

	+ *
	- No, apologize.

	+ sorry
	- See, that wasn't too hard. I'll forgive you.{topic=random}
< topic

/* ##############################
   ## Test Wink Emoticon       ##
   ############################## */

+ wink
- hehe ;)

/* ##############################
   ## Test Numeric Modifiers   ##
   ############################## */

+ do i have points
* points?=> Yes, your points are <get points>.
- Your points aren't defined.

+ set points to 0
- <set points=0>Points (re)set to 0.

+ count points
- You currently have <get points> on record.

+ delete points
- <set points=undef>Points variable deleted.

+ add * points
- <add points=<star>>Given <star> points. New value: <get points>

+ sub * points
- <sub points=<star>>Taken <star> points. New value: <get points>

+ double points
- <mult points=2>Your points have been doubled. New value: <get points>

+ cut points
- <div points=2>Your points have been cut in half. New value: <get points>

+ add to name
- <add name=5>Tried adding 5 to name.

+ points milestone
* points < 10 => You have less than 10 points.
* points < 25 => You have less than 25 points.
- You must have 25 or more points.

+ more than 25
* points >= 25 => You have more than or equal to 25 points.
- You're not there yet.

/* ##############################
   ## Test {person} Tag        ##
   ############################## */

+ do you think *
- What if I do think {person}<star>{/person}?

/* ##############################
   ## Test Environment Vars    ##
   ############################## */

+ rs version
- I am running on RiveScript version <bot ENV_APPVERSION>, or "<bot ENV_APPNAME>", running on <bot ENV_OS>.

+ change os
- Trying to change OS... {! var ENV_OS = Linux}

+ get system path
- The system path is: <bot ENV_SYS_PATH>

/* ##############################
   ## Test Empty Wildcard Bug  ##
   ############################## */

// As far as v. 0.06, if the first * was blank, <star1> would match the
// value of the second * rather than being blank.
+ *aol*
- Wildcard test matched. Star1 = <star1>; Star2 = <star2>

! array be = am are is was were

+ *i (@be)*
- Do you wish to believe you are {person}<star3>{/person}?

/* ##############################
   ## Test English Libraries   ##
   ############################## */

+ test eng (@aMinimum)
- You said <star>.