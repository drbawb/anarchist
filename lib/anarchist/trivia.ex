defmodule Anarchist.TriviaRoom do
  require Logger

  @tick_rate_ms 1000
  @max_wait_len 15

  @open_lobby """
  A round of trivia is starting!
  I will randomly ask questions until someone uses `!qstop`

  Every five seconds I will spit out a hint (if they're available.)
  If no one guesses the correct answer after 30 seconds we will move
  on to the next question.

  LET THE GAMES BEGIN.
  """

  def start(mod) do
    GenServer.start(__MODULE__, %{mod: mod, answers: [], qnum: 0, tick: 0})
  end

  def init(state), do: {:ok, state}

  def terminate(reason, state) do
    state.mod.({:say, "trivia lobby shutting down @ #{inspect self}"})
  end

  # category, prompt, response
  defp announce_question(state) do
    qnum    = state.qnum
    qcat    = state.question.category
    qprompt = state.question.prompt
    qtell   = state.question.announced

    question = case qtell do
      false -> 
        announce_resp = state.mod.({:say, "question no. #{qnum} is \\[#{qcat}\\]: #{qprompt}"})
        Logger.debug "question announced ?? #{inspect announce_resp}"
        %{state.question | announced: true}

      true -> state.question
    end

    %{state | question: question}
  end

  def announce_winner(state) do
    winner    = state.question.answered
    wall_time = state.tick - state.question.started

    cond do
      not is_nil(winner) ->
        Logger.info "dude won :: #{inspect winner}"
        state.mod.({:say, "dude won :: #{inspect winner}"})

        state
        |> Map.delete(:question)
        |> Map.put(:answers, [])

      wall_time > @max_wait_len ->
        state.mod.({:say, "question has gone #{wall_time} ticks with no winner"})
        state.mod.({:say, "the answer was: #{state.question.response}"})
        
        state
        |> Map.delete(:question)
        |> Map.put(:answers, [])

      true -> state
    end
  end

  # drains the answer queue
  defp drain_queue(state) do
    winner = List.foldl(state.answers, nil, fn {who,text}, st ->
      normalized_response = String.downcase(state.question.response)
      normalized_answer   = String.downcase(text)

      if String.contains?(normalized_answer, normalized_response) do
        who
      end
    end)

    %{state | question: %{state.question | answered: winner}}
  end

  defp load_question(state) do
    question = Map.get_lazy(state, :question, fn ->
      GenServer.call(Trivia, :random)
      |> Map.put(:announced, false)
      |> Map.put(:answered, nil)
      |> Map.put(:started, state.tick)     
    end)

    Map.put(state, :question, question)
  end

  def tick_game(state) do
    %{state | tick: state.tick + 1}
  end

  def handle_info(:tick, state) do
    Process.send_after self(), :tick, @tick_rate_ms

    next_state = state
    |> load_question()     # load a question from db if nil
    |> announce_question() # announce / offer hints on question
    |> drain_queue()       # drain response queue until a winner is found
    |> announce_winner()   # announce winner if not nil or too many ticks have passed
    |> tick_game()         # count number of game ticks

    {:noreply, next_state}
  end

  def handle_call(:init_game, _from, state) do
    Logger.info "starting trivia lobby ..."
    Process.send_after self(), :tick, @tick_rate_ms
    
    state.mod.({:say, "trivia lobby starting up in pid #{inspect self}"})
    {:reply, :ok, state}
  end

  def handle_call({:response, who, text}, _from, state) do
    Logger.info "logging response #{inspect text} from #{inspect who}"
    next_state = %{state | answers: [{who, text} | state.answers]}
    {:reply, :ok, next_state}
  end

  def handle_call(:ping, from, state) do
    Logger.info "trivia room ping from #{inspect from} => #{inspect self}"
    state.mod.({:say, "pong #{inspect from} => #{inspect self}"})
    {:reply, :ok, state}
  end
end

defmodule Anarchist.TriviaRegistry do
  use     GenServer
  require Logger
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  def init(:ok) do
    Logger.info "loading trivia modules from db/quiz-en/** ..."
    db = load_database("db/quiz-en/questions.dtron.en")
    {:ok, %{db: db, games: %{}}}
  end

  def handle_call(:dump, _from, state) do
    {:reply, state.db, state}
  end

  def handle_call({:load, path}, _from, state) do
    trivia = load_database(path)
    Logger.debug "loaded db: #{inspect trivia}"
    {:reply, :ok, %{state | db: trivia}}
  end

  @doc """
  starts a trivia lobby and registers it under the provided name
  """
  def handle_call({:start, name, mod}, _from, state) do
    games = Map.put_new_lazy(state.games, name, fn ->
      {:ok, lobby_pid} = Anarchist.TriviaRoom.start(mod)
      GenServer.call(lobby_pid, :init_game)
      lobby_pid
    end)

    {:reply, :ok, %{state | games: games}}
  end

  def handle_call({:response, room, who, text}, _from, state) do
    case Map.get(state.games, room) do
      nil      -> Logger.warn "answer w/ no game ..."
      game_pid -> GenServer.call game_pid, {:response, who, text}
    end

    {:reply, :ok, state}
  end

  def handle_call({:stop, name}, _from, state) do
    {lobby, games} = Map.pop(state.games, name)
    GenServer.stop(lobby)

    {:reply, nil, Map.put(state, :games, games)}
  end

  def handle_call(:count, _from, state) do
    {:reply, Enum.count(state.db), state}
  end

  def handle_call(:random, _from, state) do
    random_prompt = state.db |> Enum.random
    {:reply, random_prompt, state}
  end

  # loads a database in the MoxBot format
  # this format has questions separated by line breaks
  #
  #  valid keys:
  #  ----------
  #  Category?                              (should always be on top!)
  #  Question                               (should always stand after Category)
  #  Answer                                 (will be matched if no regexp is provided)
  #  Regexp?                                (use UNIX-style expressions)
  #  Author?                                (the brain behind this question)
  #  Level? [baby|easy|normal|hard|extreme] (difficulty)
  #  Comment?                               (comment line)
  #  Score? [#]                             (credits for answering this question)
  #  Tip*                                   (provide one or more hints)
  #  TipCycle? [#]                          (Specify number of generated tips)
  defp load_database(path) do
    buf = File.read!(path) |> String.split("\n")
    _parse_file(buf, %{}, [])
  end

  defp _parse_file([], cur, all), do: all
  defp _parse_file([head | tail], cur, all) do
    case head do
      "#" <> _comment -> _parse_file(tail, cur, all)

      "Category: " <> category -> _parse_file(tail, %{category: category}, [cur | all])
      "Question: " <> question -> _parse_file(tail, Map.put(cur, :prompt, question), all)
      "Answer: "   <> answer   -> _parse_file(tail, Map.put(cur, :response, answer), all)

      unknown -> 
        Logger.warn("moxdb :: ignoring unknown line: #{inspect unknown}")
        _parse_file(tail, cur, all)
    end
  end
end
