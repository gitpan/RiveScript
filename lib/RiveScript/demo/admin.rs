// Administrative functions.

+ reload{weight=10000}
* <id> eq <bot master> => Reloading brain... <call>reload</call>
- {@botmaster only}

+ force reload
- Reloading. <call>reload</call>

+ shutdown{weight=10000}
* <id> eq <bot master> => Shutting down... <call>shutdown</call>
- {@botmaster only}

+ botmaster only
- This command can only be used by my botmaster. <id> != <bot master>

> object reload perl
	my ($rs) = @_;

	# Reload the replies directory.
	$rs->loadDirectory ("./replies");
	$rs->setVariable (master => $main::master);
	$rs->sortReplies();

	return "success!";
< object

> object shutdown perl
	my ($rs) = @_;

	# Shut down.
	exit(0);
< object
