/*
	AidenBot RiveScript
	-------------------
	aiden-(kirsle|noah).rs - (kirsle|noah)Stuff
*/

+ who is (kirsle|noah)
- He's the one who created me. I know I try to sound human but when we talk about {formal}<star>{/formal} it just can't be done. :-P

+ how old is (kirsle|noah)
- Last time I checked, he's 18.

+ is (kirsle|noah) a (@malenoun) or a (@femalenoun)
- He's a boi.

+ where is (kirsle|noah) from
- Same place I am, silly! :-P

+ where is (kirsle|noah)
- What am I, his keeper?

+ yes
% what am i his keeper
- He's not here.

+ go wake up kirsle
- I shall try making an internal beep and see if it gets his attention.
& if (!exists $main::aiden->{clients}->{$id}->{_beeped}) {
&   $main::aiden->{clients}->{$id}->{_beeped} = 1;
& }
& if ($main::aiden->{clients}->{$id}->{_beeped} <= 2) {
&   $main::aiden->{clients}->{$id}->{_beeped}++;
&   print "\a";
& }
& else {
&   $reply = "You are just trying to be annoying. I'm not beeping him again.";
& }

+ wake up (kirsle|noah)
@ go wake up (kirsle|noah)
+ wake (kirsle|noah) up
@ go wake up (kirsle|noah)
+ wake up noah
@ go wake up (kirsle|noah)
+ wake noah up
@ go wake up (kirsle|noah)
+ go wake up noah
@ go wake up (kirsle|noah)