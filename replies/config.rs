/*
	RiveScript // Example config file

	This bit of code sets up globals for the
	RiveScript interpreter to follow.
*/

/* Setting "replies" causes a warning
! global replies = test */
! global split_sentences = 1
! global sentence_splitters = . ! ? ;

/* Person Substitutions */
! person i     = you
! person my    = your
! person mine  = yours
! person me    = you
! person am    = are
! person you   = I
! person your  = my
! person yours = mine
! person are   = am

/* Set some message substitutions */

! sub i'm = i am
! sub i'd = i would
! sub i've = i have
! sub i'll = i will
! sub don't = do not
! sub isn't = is not
! sub you'd = you would
! sub you're = you are
! sub you've = you have
! sub you'll = you will
! sub he'd = he would
! sub he's = he is
! sub he'll = he will
! sub she'd = she would
! sub she's = she is
! sub she'll = she will
! sub they'd = they would
! sub they've = they have
! sub they're = they are
! sub they'll = they will
! sub we'd = we would
! sub we're = we are
! sub we've = we have
! sub we'll = we will
! sub whats = what is
! sub what's = what is
! sub what're = what are
! sub what've = what have
! sub what'll = what will
! sub can't = can not
! sub whos = who is
! sub who's = who is
! sub who'd = who would
! sub who'll = who will
! sub don't = do not
! sub didn't = did not
! sub it's = it is
! sub could've = could have
! sub should've = should have
! sub would've = would have
! sub ;) = wink
! sub ;-) = wink

/* Set some botvariables */

! var name  = Casey Rive
! var age   = 14
! var sex   = male
! var quote = How much wood would a woodchuck
	^ chuck if a woodchuck could chuck wood?

/* Set some arrays */

! array colors  = red blue green yellow cyan fuchsia
	^ white black gray grey orange pink
	^ turqoise magenta gold silver
! array numbers = 0 1 2 3 4 5 6 7 8 9

// Delete the numbers array.
! array numbers = undef