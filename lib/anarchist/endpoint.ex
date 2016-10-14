defmodule Anarchist.Endpoint do
  use Slack
  require Logger

  @moduledoc """
  This module provides the main Slack RTM endpoint.

  The endpoint listens for commands on all channels its API ky has been
  invited to, however it will only output to the channel specified by the
  `@channel` module attribute.
  """

  @channel "#random"

  def handle_connect(slack) do
    Logger.info "connected :: as #{slack.me.name}"
  end

  @doc """
  Handles any events w/ type `message` from the Slack RTM API.

  Messages which start with a command prefix are handled accordingly
  by parsing the command and dispatching it to the appropriate server
  module in a synchronous fashion.

  The following commands are supported:

  ## Misc

  ```
  !help          :: prints the bots usage information to the channel
  !soup          :: sends a bowl of soup to this user
  !soup <target> :: sends a bowl of soup to target user
  <ALL CAPS>     :: stores this message in the bot's shout DB
  ```

  ## Polling

  ```
  !poll  <prompt> :: sets this user's poll prompt
  !polla <prompt> :: adds an answer-prompt to the user's poll
  !pollr          :: runs the user's poll
  !polle          :: stops the user's poll
  ```
  """
  def handle_message(message = %{type: "message"}, slack) do
    case Map.get(message, :text) do
      "!help" ->
        from = Slack.Lookups.lookup_user_name(message.user, slack)

        help_text = """
        Hi #{from}, I'm @anarchist, the chaos-bot.

        I conduct simple multiple choice polls on your behalf.
        I log all responses to your poll in my VAST DATABANKS and
        I can print out a summary of your poll at any time.

        At the moment I can only run one poll per user account, though
        I can conduct multiple polls simultaneously.

        Here is a list of commands I understand:

        - `!poll <prompt>`:  (re)start your poll with the question provided
        - `!polla <prompt>`: add a valid response to your current poll
        - `!pollr`:          starts your poll and tells users how to respond
        - `!polle`:          prints out the current summary of responses to your poll
        """

        send_message(help_text, @channel, slack)
      "!catfact" ->
        factoid = GenServer.call CatFacts, :fact
        send_message(factoid, @channel, slack)

      "!soup" ->
        from = Slack.Lookups.lookup_user_name(message.user, slack)
        send_message("*#{slack.me.name} gives #{from} a bowl of soup.*", @channel, slack)

      "!soup " <> to ->
        rex  = ~r/\<@(?<name>\w+)\>/
        name = Regex.named_captures(rex, to)["name"]
        to   = Slack.Lookups.lookup_user_name(name, slack)

        send_message("*#{slack.me.name} gives #{to} a bowl of soup.*", @channel, slack)

      # setup a new prompt
      "!poll " <> prompt ->
        from = Slack.Lookups.lookup_user_name(message.user, slack)

        Logger.debug "open poll for user :: #{from} :: #{prompt}"
        GenServer.call Poller, {:open, from, prompt}

      # add an answer to the last opened prompt
      "!polla " <> answer ->
        from = Slack.Lookups.lookup_user_name(message.user, slack)

        Logger.debug "add resp for user poll :: #{from} :: #{answer}"
        GenServer.call Poller, {:add_answer, from, answer}

      # conduct this user's poll
      "!pollr" ->
        from = Slack.Lookups.lookup_user_name(message.user, slack)

        {:ok, poll} = GenServer.call Poller, {:start, from}
        Logger.debug "running poll :: #{inspect poll}"

        answer_text = poll.answers
        |> Enum.reverse
        |> Enum.with_index
        |> Enum.map(fn {el,idx} -> "#{idx+1}. #{el}" end)
        |> Enum.join("\n")

        poll_summary = """
        #{from} wants to know: #{poll.prompt}
        #{answer_text}

        To vote type: !vote #{from} <answer #>
        ex: `!vote #{from} 1` will store your vote for option #1

        You can change your vote at any time by casting a vote again
        until the poll has been closed.
        """

        send_message(poll_summary, @channel, slack)

      "!polle" ->
        from = Slack.Lookups.lookup_user_name(message.user, slack)

        Logger.debug "stopping poll"
        {:ok, poll, answers} = GenServer.call Poller, {:stop, from}
        # {:ok, %{0 => %{text: "herp", votes: 1}}}

        answer_text = Map.to_list(answers)
        |> Enum.map(fn {key,val} -> "#{key + 1}. (#{val.votes} votes) #{val.text}" end)
        |> Enum.join("\n")

        poll_summary = """
        The results are in for #{from}'s poll: #{poll.prompt}

        Responses:
        #{answer_text}
        """

        send_message(poll_summary, @channel, slack)

      # vote in someone elses poll
      "!vote " <> response ->
        regex    = ~r/\<@(?<target>\w+)\> (?<idx>\d+)/
        captures = Regex.named_captures(regex, response)

        from = Slack.Lookups.lookup_user_name(message.user, slack)
        to   = Slack.Lookups.lookup_user_name(captures["target"], slack)

        Logger.debug "voting #{captures["idx"]} in #{captures["target"]}"
        GenServer.call Poller, {:vote, from, to, captures["idx"]}

      text -> process_text(text, slack)
    end

    Logger.info "got message :: #{inspect message}"
  end

  def handle_message(_,_), do: :ok

  # handle infos
  def handle_info({:message, text, channel}, slack) do
    Logger.info "Sending your message, captain!"
    send_message(text, channel, slack)
    {:ok}
  end

  def handle_info(_, _), do: :ok

  def process_text(text, slack) do
    if (not is_nil(text) and String.upcase(text) == text) do
      Logger.debug "user shouted at me ... [#{text}]"
      random  = GenServer.call(Shouter, :random)
      _store  = GenServer.call(Shouter, {:add, text})

      send_message(random, @channel, slack)
    end
  end
end
