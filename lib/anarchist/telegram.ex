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
    GenServer.start_link(__MODULE__, nil, opts)
  end

  # dispatch an incoming chat message to appropriate bot module
  def handle_cast({:dispatch, room_id, text}, state) do
    case text do
      "!crash" -> raise "OH SHIT!!!!"

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

      "!" <> _cmd ->
        Yocingo.send_message(room_id, @misunderstood)

      "Kimi no namae wa?" ->
        Yocingo.send_message(room_id, @megumeme)

      text when not is_nil(text) -> process_text(room_id, text)
      _ -> Logger.warn "bot could not dispatch message"
    end

    {:noreply, state}
  end

  # stores shouts in the shout db, otherwise does nothing
  defp process_text(room_id, text) do
    if Anarchist.Shouter.valid_shout(text, true) do
      Logger.debug "user shouted at me ..."
      random  = GenServer.call(Shouter, :random)
      _store  = GenServer.call(Shouter, {:add, text})

      Yocingo.send_message(room_id, random)
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
      message   = update["message"]
      room_id   = message["chat"]["id"]
      text      = message["text"]

      Logger.debug "telegram :: #{inspect message}"
      Logger.debug "telegram :: #{room_id} :: #{inspect text}"
      GenServer.cast(TGServ, {:dispatch, room_id, text})
    end
  end

  # grabs the largsest update id we've seen in this batch
  defp last_update_from(updates) do
    results = updates["result"]
    List.foldl(results, 0, fn el,acc -> max(acc, el["update_id"]) end)
  end
end
