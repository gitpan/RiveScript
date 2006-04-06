/*
	RiveScript // Example simple reply file

	These are just simple replies to hello's and
	goodbye's.
*/

+ (hello|hey|hi|hola|yo|shorah)
- Hello there human.{weight=19}
- Hey, how are you?{weight=1}

+ (bye|goodbye|ttyl)
- Talk to you later, human.

/* ##############################
   ## Knock Knock              ##
   ############################## */

+ knock knock
- Who's there?

+ *
% who is there
- <star> who?

+ knock knock
% * who
- Who's there?

+ *
% * who
- Ha! <star>! That's hilarious!