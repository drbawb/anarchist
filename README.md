# Anarchist

Authorized users can start a poll w/ the command:

	!poll  <question>
	!polla <option>
	!polla <option>
	!polla <option>

	!pollr :: run the poll (print how to vote)
	!polle :: stop the poll (print summary of votes)

	!vote <option> :: logs this user's vote for this option

`@anarchist` also knows a few silly commands such as: !soup, !help, etc.

There is also a "shout db" which logs shouts from the chatroom and
repeats a random one whenever a new shout is entered into the record.

The shout server can be persisted & populated from a JSON file.
There is an occasional watchdog that persists the database to
the path `db/shouts.txt` automatically.

This path is also read on system startup, unless configured otherwise.
