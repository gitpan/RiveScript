/*
	RiveScript // Begin Example

	This reply set is checked before chatting can begin.
	If it fails to return an {ok} then the brain isn't
	utilized.
*/

// Include English
// ! include English.rsl

> begin
	// There will be a 50/50 chance he won't allow it
	+ request
	* mood = angry => {@i am angry}
	* mood = swear => {topic=apology}{ok}
	* name ? => Your name is <get name>. {ok}
	- {ok}
//	- I'm not allowing your request right now. Try again. ;)

	+ i am angry
	- I'm angry right now.
	- I don't want to talk.
	- Go away.
< begin

// This is to test the "angry" condition in begin
+ set mood to angry
- {! var mood = angry}I have set my mood to angry.

+ test force a topic
- {! var mood = swear}On your next message I'll force a topic on you.