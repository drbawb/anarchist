defmodule Anarchist.Telegram do
  @moduledoc """
  The anarchist telegram endpoint consists of two processes:

  - an OTP gen server which processes messages and tries to reply to them

  - an HTTP long poller which receives and confirms messages from telegram's
    bot API endpoint

  The long poller cannot be safely restarted as it blocks internally, but
  the bot server can be modified at will since it is a normal OTP behaviour.
  """

  def start_link(opts \\ []) do
    import Supervisor.Spec, warn: false

    children = [
      worker(Anarchist.TGServer, [[name: TGServ]]),
      worker(Anarchist.TGPoller, [[name: TGPoll]]),
    ]

    opts = [strategy: :one_for_one, name: Anarchist.Telegram]
    Supervisor.start_link(children, opts)
  end
end

defmodule Anarchist.TGServer do
  use GenServer
  require Logger

  @moduledoc """
  The Telegram Bot Server.

  This parses, dispatches, and replies to commands received from the
  Telegram bot API. Failure in this module is non-fatal and should not
  affect the processing of unrelated commands.
  """

  # meme blocks
  @megumeme """
  WAGA NA WA MEGUMIN.
  My calling is that of an arch wizard, one who controls explosion magic, the strongest of all offensive magic!

  I desire for my torrent of power a destructive force: a destructive force without equal! Return all creation to cinders, and come from the abyss!

  This is the mightiest means of attack known to man, the ultimate attack magic!

  **EXPLOSION!**
  """

  # help blocks
  @misunderstood "I'm sorry, I don't recognize that command, do you need `!help`?"
  @card_text """
  WOOT. Somebody wants to play Cards Against Humanity!
  To join the game type: `/cards join` in this channel.

  Once the game begins I will select a czar at random.
  After that we will rotate through the players in order
  until someone reaches seven points, or the game crashes
  because @kotokun is a shit coder.

  Game play will proceed as follows:

  - I will deal cards to ensure each player has 10 cards
  - I will announce the black card in the public chat
  - All non-czar players will receive a private message
    which repeats the prompt, and displays your hand of cards
    which you may choose from.

  Once all players have chosen a card: the choices will be
  revealed in the group chat, and the czar will pick the
  most hilarious one at their leisure.

  At this point a new czar will be selected and the game
  will proceed to the top of the round.
  """

  @help_text """
  I'm anarchist, the lemon chicken chatbot.
  I know a few commands, such as:

  ```
  !help          :: prints this message
  !catfact       :: prints a random cat fact
  !cave          :: prints a random cave johnson fact
  !chuck         :: chuck norris facts
  !roll XdY      :: roll some dice!
  !ron           :: wisdom of ron swanson
  !trump         :: print Trump's inanity
  !weather <zip> :: fetches a weather report
  <ALL CAPS>     :: teaches me about emotions
  ```

  Feel free to give them a try!
  """

  # start the telegram bot serv
  def start_link(opts \\ []) do
    Logger.info "telegram bot serv is starting ..."
    {:ok, cah_lobbies} = Agent.start(fn -> %{} end, [])
    {:ok, cah_players} = Agent.start(fn -> %{} end, [])
    GenServer.start_link(__MODULE__, %{lobbies: cah_lobbies, players: cah_players}, opts)
  end

  # dispatch callback buttons
  def handle_cast({:callback, uuid, from, body}, state) do

    case body do
      "cah.czar." <> winner ->
        winner  = String.to_integer(winner)
        user_id = from["id"]

        Agent.get(state.players, fn el ->
          room_id     = Map.get(el, user_id)
          lobby_pid   = Agent.get(state.lobbies, fn el -> Map.get(el, room_id) end)
          {:ok, resp} = GenServer.call(lobby_pid, {:czar, user_id, winner})
        end)

      "cah.pick." <> idx ->
        Logger.debug "user #{inspect from} chose cah card ##{inspect idx}"

        Agent.get(state.players, fn el ->
          user_id   = from["id"]
          card_idx  = String.to_integer(idx)

          # find lobby this pick belongs to
          room_id     = Map.get(el, user_id)
          lobby_pid   = Agent.get(state.lobbies, fn el -> Map.get(el, room_id) end)
          {:ok, resp} = GenServer.call(lobby_pid, {:pick, user_id, card_idx})

          TeleFrag.ack(uuid, resp)
        end)


      _ ->
        Logger.debug "unhandled callback :: #{inspect body}"
        TeleFrag.ack(uuid, "cool beans.")
    end

    {:noreply, state}
  end

  # dispatch an incoming chat message to appropriate bot module
  def handle_cast({:dispatch, room_id, text, msg}, state) do
    case text do
      "!crash" -> raise "OH SHIT!!!!"

      "/cards" ->
        Agent.update(state.lobbies, fn el ->
          {:ok, lobby_pid} = CardRoom.start_link([])
          Yocingo.send_message(room_id, @card_text)
          Map.put(el, room_id, lobby_pid)
        end)

      "/cards join" ->
        Logger.debug "#{inspect msg} wants to join"
        Agent.get(state.lobbies, fn el ->
          lobby_pid = Map.get(el, room_id)
          user_id   = msg["from"]["id"]
          username  = msg["from"]["first_name"]

          {:ok, players} = GenServer.call(lobby_pid, {:join, user_id, username})
          players = players
          |> Enum.map(fn {_k,el} -> el.name end)
          |> Enum.join(", ")

          Agent.update(state.players, fn el ->
            Map.put(el, user_id, room_id)
          end)

          msg = """
          #{username} has joined your struggle!
          Now playing: #{players}
          """

          Yocingo.send_message(room_id, msg)
        end)

      "/cards just do it" ->
        runmod = fn msg ->
          case msg do
            {:say, text}      -> TeleFrag.send(room_id, text)
            {:priv, id, text} -> TeleFrag.send(id, text)

            {:choose, text, verb, buttons} ->
              buttons = for row <- buttons do
                for col <- row do
                  id   = col[:id]
                  text = col[:text]
                  [callback_data: "cah.#{verb}.#{id}", text: text]
                end
              end

              # send reply
              reply_k = JSX.encode!([inline_keyboard: buttons])
              TeleFrag.send(room_id, text, [reply_markup: reply_k])

            {:choose, id, text, verb, buttons} ->
              # format buttons for telegram bot API
              buttons = for row <- buttons do
                for col <- row do
                  id   = col[:id]
                  text = col[:text]
                  [callback_data: "cah.#{verb}.#{id}", text: text]
                end
              end

              # send reply
              reply_k = JSX.encode!([inline_keyboard: buttons])
              TeleFrag.send(id, text, [reply_markup: reply_k])

            _ -> "unhandled cah callback"
          end
        end

        Agent.get(state.lobbies, fn el ->
          lobby_pid = Map.get(el, room_id)
          case GenServer.call(lobby_pid, {:start, runmod}) do
            :ok -> Yocingo.send_message(room_id, "here we go!")
            {:error, msg} -> Yocingo.send_message(room_id, msg)
          end
        end)

      "/cards kill" ->
        Agent.get(state.lobbies, fn el ->
          lobby_pid = Map.get(el, room_id)
          GenServer.call(lobby_pid, :score)
          GenServer.stop(lobby_pid)
        end)

      "!sys" ->
        factoid = GenServer.call CatFacts, :sys
        Logger.debug "#{inspect Yocingo.send_message(room_id, factoid)}"

      "!help" ->
        Yocingo.send_message(room_id, @help_text)

      "!catfact" ->
        factoid = GenServer.call CatFacts, :fact
        Yocingo.send_message(room_id, factoid)

      "!cave" ->
        factoid = GenServer.call CatFacts, :cave
        Yocingo.send_message(room_id, factoid)

      "!chuck" ->
        factoid = GenServer.call CatFacts, :chuck
        Yocingo.send_message(room_id, factoid)

      "!roll " <> dspec ->
        rex = ~r/(?<num>\d+)d(?<type>\d+)/
        res = Regex.named_captures(rex, dspec)
        {num, type} = {res["num"], res["type"]}

        unless is_nil(num) or is_nil(type) do
          Logger.info "rolling #{num} of #{type}"
          dicerep = GenServer.call Dice, {:roll, num, type}
         
          Logger.info "got rep: #{dicerep}"
          Yocingo.send_message(room_id, dicerep)
        end

      "!ron" ->
        factoid = GenServer.call CatFacts, :ron
        Yocingo.send_message(room_id, factoid)

      "!trump" ->
        factoid = GenServer.call CatFacts, :trump
        Yocingo.send_message(room_id, factoid)

      "!trump " <> subj ->
        factoid = GenServer.call CatFacts, {:trump, subj}
        Yocingo.send_message(room_id, factoid)

      "!weather " <> zip ->
        factoid = GenServer.call CatFacts, {:weather, zip}
        reply = """
        temperature: #{factoid[:deg_c]}C (#{factoid[:deg_f]}F)
        outside the batcave: #{factoid[:meta]}

        sunrise at :: #{factoid[:sunrise_at] |> DateTime.to_string}
        sunset at  :: #{factoid[:sunset_at]  |> DateTime.to_string}
        """

        Yocingo.send_message(room_id, reply)

      "!qcount" ->
        num_q = GenServer.call(Trivia, :count)
        Yocingo.send_message(room_id, "loaded #{num_q} questions")

      "!qstart" ->
        Logger.debug "requesting trvia for :: #{inspect room_id}"
        GenServer.call Trivia, {:start, room_id, fn(msg) ->
          case msg do
            {:say, text} ->
              Logger.debug "sending trivia message #{text} => #{room_id}"
              Yocingo.send_message(room_id, text)

            _ -> Logger.debug "unhandled trivia callback :: #{inspect msg}"
          end
        end}

      "!qstop" ->
        Logger.debug "stopping trivia for :: #{inspect room_id}"
        GenServer.call Trivia, {:stop, room_id}


      "!" <> cmd ->
        if String.match?(cmd, ~r/\w+/) do
          Yocingo.send_message(room_id, @misunderstood)
        end

      "Kimi no namae wa?" ->
        Yocingo.send_message(room_id, @megumeme)

      text when not is_nil(text) -> process_text(room_id, text, msg)
      _ -> Logger.warn "bot could not dispatch message"
    end

    {:noreply, state}
  end

  # stores shouts in the shout db, otherwise does nothing
  defp process_text(room_id, text, msg) do
    GenServer.call Trivia, {:response, room_id, msg["chat"]["username"], text}

    if Anarchist.Shouter.valid_shout(text) do
      Logger.debug "user shouted at me ..."
      random  = GenServer.call(Shouter, :random)
      _store  = GenServer.call(Shouter, {:add, text})

      cond do
        String.contains?(random, "GROPING") -> 
          Yocingo.send_photo(room_id, "db/whole-hearted-groping.jpg", random)

        true -> Yocingo.send_message(room_id, random)
      end

    end
  end
end

defmodule Anarchist.TGPoller do
  require Logger

  @moduledoc """
  The telegram bot API long polling server.

  This server blocks on an HTTP request to the Telegram Bot API (v1).
  To avoid continually processing bad requests: we `cast` to the actual
  command dispatcher running in another process.

  Meanwhile this process immediately confirms the message, so that
  any crashes in this module will not see the bad request ad infinitum.
  """

  def start_link(opts \\ []) do
    Logger.info "telegram poller is starting"
    Logger.info "i am the walrus :: #{inspect Yocingo.get_me}"
    Task.start_link(fn -> main_loop(0) end)
  end

  @doc """
  Long polls for messages continuously.

  Each iteration of this function is started w/ the
  highest update-id the loop has seen so far, the telegram
  API will only send us "unconfirmed messages" >= that ID.

  This dispatches messages to the botserv and then polls again immediately.
  """
  def main_loop(last_update) do
    updates        = Yocingo.get_updates(last_update)
    next_update_id = last_update_from(updates) + 1
    process_updates(updates)
    main_loop(next_update_id)
  end

  # dispatches updates to handlers
  defp process_updates(updates) do
    results = updates["result"]

    for update <- results do
      callback = update["callback_query"]
      message  = update["message"]

      cond do
        not is_nil(message) ->
          room_id   = message["chat"]["id"]
          msg_id    = message["message_id"]
          text      = message["text"]

          Logger.debug "telegram :: #{room_id} :[#{msg_id}]: #{inspect text}"
          GenServer.cast(TGServ, {:dispatch, room_id, text, message})

        not is_nil(callback) ->
          uuid = callback["id"]
          user = callback["from"]
          data = callback["data"]

          Logger.debug "telegram :: #{inspect callback}"
          GenServer.cast(TGServ, {:callback, uuid, user, data})

        true -> Logger.warn "unknown API message :: #{inspect update}"
      end
    end
  end

  # grabs the largsest update id we've seen in this batch
  defp last_update_from(updates) do
    # Logger.debug "updates in case it crashes :: #{inspect updates}"
    results = updates["result"]
    List.foldl(results, 0, fn el,acc -> max(acc, el["update_id"]) end)
  end
end
