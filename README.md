# `anarchist`

anarchist is a chat-bot written for `the lemon chicken sandwich`, 
quite possibly the greatest group chat which ever existed.

the anarchist source code can be roughly categorized as
two types of modules:

- endpoints: parse commands and replies
- module servers: plugins that power the brain  

At the moment there are two endpoints:

- The Slack RTM endpoint
- The Telegram HTTP (polling) endpoint

As well as a number of modules:

- DB Backup Scheduler
- CatFacts (TM)
- Dice Roller
- Poll Server
- Shout Server
- Trivia Server


## CatFacts

This module collects information from a number of high-quality
sources to provide users with hours of entertainment.

Supported commands include:

  - !catfact       :: accept no substitutes
  - !cave          :: cave johnson quotes (requires flat-file DB)
  - !chuck         :: chuck norris quotes
  - !ron           :: ron swanson quotes
  - !trump         :: trump's babbling
  - !weather <zip> :: what is this "outside" you speak of?


## Democracy Engine

Authorized users can start a poll w/ the command:

	!poll  <question>
	!polla <option>
	!polla <option>
	!polla <option>

	!pollr :: run the poll (print how to vote)
	!polle :: stop the poll (print summary of votes)

	!vote <option> :: logs this user's vote for this option

`@anarchist` also knows a few silly commands such as: !soup, !help, etc.

## Dice Roller

Users can submit a dice spec such as: `!roll NdF`

The bot will take `N` samples of uniform randomness ranging from `1 to F`
and return the result to the user.

For e.g:

  > !roll 6d8
  > You rolled: [4, 7, 2, 1, 6, 3]; sum = 23


## Shout Server

There is a shared "shout db" which looks for users shouting in the chatroom.
The shout is submitted for considreation to THE GREAT RECORD and anarchist then
replays a random shout from the record for lulz and posterity.

The shout server can be persisted & populated from a JSON file containing an array
of strings. Duplicates will be ignored as this array is deserialized into a hash-set.

There is an occasional watchdog that persists the database to
the path `db/shouts.txt` automatically. The backup daemon reloads this file
on system startup unless configured to do otherwise.

## Trivia Server

_UNDER DEVELOPMENT_

This consists of two pieces: the trivia registry, and any number of
trivia room instances.

The lobby is responsible for loading quiz DBs (in the MoxQuiz format) as
well as mapping bot endpoints to trivia rooms.

An endpoint can request a new lobby from the registry (or retrieve the PID
of an already running trivia room.)

The endpoint can submit reponses to the trivia registry, which will be disapatched
to the appropriate trivia room for consideration.

Lastly an endpoint can stop a running lobby by asking the registry nicely.

### Database Format

At the moment we load databases in the MoxQuiz format.

- Lines starting with "#" are ignored.
- Lines starting with "Question:" start a new record
- "Category:" marks the category
- "Answer:" marks the answer
- TODO: support `RegExp` field for less restrictive answers
