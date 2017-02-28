# start of game
## each player draws 10 cards

# top of round
## person who most recently pooped begins as czar
## plays black card
## players play white card(s) face down
## players draw to replace 10 cards

# bottom of round
## white cards are revealed
## czar picks the best one
## player of that card gets a point

# bottom of game
## game ends when someone reaches 7 points
## alternatively game ends when the server crashes
## because there's no more cards ....

# from this we see the game proceeds through a few phases
# :pick_czar      (choose next czar, play black card)
# :prompt_players (prompt all non-czars to pick white card)
# :wait_responses 
# :wait_czar      
#
# the two wait states are simply timeouts for afk players
# these states can be interrupted via events
# (namely: last player submits response, czar picks winner)
# 
# the pick_czar phase will deal everyone back up to 10

defmodule CardRoom do
  use     GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  def init(:ok) do
    state = %{
      mod:   nil,
      mode:  :pick_czar,
      picks: %{},

      # timers & idx
      czar: 0,
      tick: 0,
      wait: 0,

      players: %{}, # players (score, flags, hand)
      cdb: nil,     # cards database (ets)
    }

    {:ok, %{state | cdb: load_db()}}
  end

  defp load_db do
    qdb = File.read!("db/cah/questions.txt") |> String.split("\n") |> Enum.shuffle
    adb = File.read!("db/cah/answers.txt")   |> String.split("\n") |> Enum.shuffle
    cdb = :ets.new(:cards, [:set, :protected])
    
    :ets.insert(cdb, {:adb, adb})
    :ets.insert(cdb, {:qdb, qdb})
    :ets.insert(cdb, {:adis, []})
    :ets.insert(cdb, {:qdis, []})

    cdb
  end

  defp add_player(state, player, true), do: state
  defp add_player(state, player, false) do
    players = state.players |> Map.put(player.uid, player)
    state   = state|> Map.put(:players, players)
  end

  defp init_player(uid, name), do: %{uid: uid, name: name, hand: [], rounds_won: 0}

  def handle_call(:dump, _from, state) do
    {:reply, state, state}
  end

  # players enter the queue
  def handle_call({:join, uid, name}, _from, state) do
    is_running = state.tick > 0
    state = add_player(state, init_player(uid, name), is_running)
    {:reply, {:ok, state.players}, state}
  end

  # player plays card from their hand
  # this might bump us into pick_czar mode ...
  def handle_call({:pick, uid, idx}, _from, %{mode: :wait_players} = state) do
    picks = Map.put(state.picks, uid, idx)
    card  = Enum.at(state.players[uid].hand, idx)
    all_players_in = (Enum.count(state.players) - 1) == Enum.count(picks)

    # figure out if we are ready to pick a winner
    state = if all_players_in do
      buttons = for {user,pick} <- picks do
        card = Enum.at(state.players[user].hand, pick)
        [[id: "#{user}", text: card]]
      end

      state.mod.({:choose, "The answers are in: #{}", "czar", buttons})
      %{state | mode: :wait_czar, picks: picks}
    else
      %{state | picks: picks}
    end

    {:reply, {:ok, "Set pick to: #{card}"}, state}

  end

  # fall through if mode isn't `wait_players`
  def handle_call({:pick, uid, idx}, _from, state) do
    {:reply, {:ok, "Sorry but this round is over ..."}, state}
  end

  def handle_call({:czar, uid, winner}, _from, state) do
    {_,czar} = Enum.at(state.players, state.czar)

    if uid == czar.uid do
      winner = Map.get(state.players, winner)
      white  = Enum.at(winner.hand, Map.get(state.picks, winner.uid))

      state.mod.({:say, "The winner is: #{winner.name} with #{white}"})

      # remove played cards from hands ...
      players = for {user,player} <- state.players, into: %{} do
        hand = case Map.get(state.picks, user) do
          nil  -> player.hand
          pick -> List.delete_at(player.hand, pick)
        end

        rounds_won = if user == winner.uid, do: player.rounds_won + 1, else: player.rounds_won
        {user, %{player | rounds_won: rounds_won, hand: hand}}
      end

      # update the state
      state  = %{state | mode: :pick_czar, picks: %{}, players: players}
      {:reply, {:ok, "good jorb."}, state}
    else
      {:reply, {:ok, "OMG DONT PRESS THAT. YOU'RE NOT THE CZAR."}, state}
    end
  end

  # begin event loop
  def handle_call({:start, mod}, _from, state) do
    cond do
      Enum.count(state.players) < 1 ->
        {:reply, {:error, "you're gonna play by yourself? *snrk*"}, state}

      state.tick == 0 ->
        Process.send_after(self(), :tick, 100)
        {:reply, :ok, %{state | mod: mod}}

      state.tick != 0 -> 
        {:reply, {:error, "already running"}, state}
    end
  end

  def handle_call(:score, _from, state) do
    scores = state.players
    |> Enum.map(fn {_k,el} -> {el.rounds_won, el.name} end)
    |> Enum.sort(fn {w1,_}, {w2,_} -> w1 > w2 end)
    |> Enum.map(fn {wins,who} -> "#{who} with #{wins} points" end)
    |> Enum.join("\n")

    state.mod.({:say, "#{scores}"})
    {:reply, :ok, state}
  end

  # play a random hand for lulz
  def handle_call({:omg, room}, _from, state) do
    prompt  = state.qdb |> Enum.random
    answers = state.adb 
    |> Enum.shuffle
    |> Enum.take(7)
    |> Enum.with_index
    |> Enum.map(fn {el,id} -> [[callback_data: "#{id}", text: el]] end)

    Logger.debug "prompt => #{inspect prompt}"
    Logger.debug "answers => #{inspect answers}"

    buttons = JSX.encode!([inline_keyboard: answers])
    resp = TeleFrag.send(room, "black card :: #{prompt}", [reply_markup: buttons])

    {:reply, resp, state}
  end

  def handle_info(:tick, state) do
    state = case state.mode do
      :pick_czar ->
        state
        |> deal_players()
        |> pick_next_czar()
        |> pick_black_card()

      :wait_players -> state # TODO: timeout
      :wait_czar    -> state # TODO: timeout
    end

    Process.send_after(self(), :tick, 1000)
    {:noreply, tick_game(state)}
  end

  # advance game clock by one unit
  defp tick_game(state), do: %{state | tick: (state.tick + 1)}

  # make sure everyone has ten cards
  def deal_players(state) do
    # loop over each player, build their hand up to 10...
    players = for {uid,player} <- state.players, into: %{} do
      cards_needed = 10 - Enum.count(player.hand)

      # pop cards off top of deck
      deck = :ets.take(state.cdb, :adb)[:adb]
      {taken, remain} = Enum.split(deck, cards_needed)
      :ets.insert(state.cdb, {:adb, remain})

      if Enum.count(taken) < cards_needed do
        raise "ran out of cards while dealing ..."
      end

      {uid, %{player | hand: player.hand ++ taken}}
    end

    hand_sizes = Enum.map(players, fn {k,v} -> Enum.count(v.hand) end)
    Logger.debug "hand sizes :: #{inspect hand_sizes}"

    %{state | players: players}
  end

  # assign a czar
  def pick_next_czar(state) do
    czar_idx   = rem((state.czar + 1), Enum.count(state.players))
    {_id,czar} = Enum.at(state.players, czar_idx)
    Logger.warn "next czar is :: #{inspect czar}"
    state.mod.({:say, "next czar is #{czar.name}"})

    %{state | czar: czar_idx}
  end

  # picks a black card and prompts for responses
  # puts the game into `:wait_players` state
  def pick_black_card(state) do
    deck = :ets.take(state.cdb, :qdb)[:qdb]
    {[card], remain} = Enum.split(deck, 1)
    :ets.insert(state.cdb, {:qdb, remain})
    
    # Logger.warn "next black card is :: #{inspect card}"
    Logger.warn "sending: #{card}"
    state.mod.({:say, "the next black card is: #{card}"})

    for {id,player} <- state.players do
      if id != state.czar do
        card_buttons = player.hand
        |> Enum.with_index
        |> Enum.map(fn {el,idx} -> [[id: idx, text: el]] end)
        caption = "The black card is: `#{card}`"
        state.mod.({:choose, id, caption, "pick", card_buttons})
      end
    end

    %{state | mode: :wait_players}
  end
end

defmodule TeleFrag do
  @bot_api "https://api.telegram.org/bot"

  defp build_url(method) do
    @bot_api <> Application.get_env(:yocingo, :token) <> "/" <> method
  end

  def send(room, text, opts \\ []) do
    body = [chat_id: room, text: text]
    body = {:form, Keyword.merge(body, opts)}
    HTTPoison.post(build_url("sendMessage"), body)
  end

  def ack(uuid, text) do
    body = {:form, [callback_query_id: uuid, text: text]}
    HTTPoison.post(build_url("answerCallbackQuery"), body)
  end
end
