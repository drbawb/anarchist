defmodule Anarchist.Poll do
  @the_question "What is the answer to life, the universe, and everything?"

  defstruct prompt: @the_question, running: false, answers: [], votes: %{}
end

defmodule Anarchist.Poller do
  use GenServer
  require Logger

  @moduledoc """
  This module maintains current poll state.
  Each user can maintain a maximum of one poll,
  and each user can only vote once per unique poll.
  """

  def start_link(opts \\ []) do
    init_state = %{ polls: %{} }

    GenServer.start_link(__MODULE__, init_state, opts)
  end

  def handle_call(:dump, _from, state) do
    Logger.debug "poller state :: #{inspect state}" 

    {:reply, :ok, state}
  end

  def handle_call({:open, uid, prompt}, _from, state) do
    user_poll = %Anarchist.Poll{prompt: prompt}
    new_polls = Map.put(state.polls, uid, user_poll)

    {:reply, :ok, %{state | polls: new_polls}}
  end

  def handle_call({:vote, from, to, resp}, _from, state) do
    case Map.get(state.polls, to) do
      nil  -> {:reply, {:error, "You don't have a poll running."}, state}
      poll ->
        new_votes = Map.put(poll.votes, from, resp)
        new_poll  = %{poll | votes: new_votes}
        new_state = %{state | polls: Map.put(state.polls, to, new_poll)}

        {:reply, :ok, new_state}
    end
  end

  def handle_call({:start, uid}, _from, state) do
    case Map.get(state.polls, uid) do
      nil  -> {:reply, {:error, "You don't have a poll running."}, state}
      poll ->
        # create and return a summary
        {:reply, {:ok, poll}, state}
    end
  end

  def handle_call({:stop, uid}, _from, state) do
    case Map.get(state.polls, uid) do
      nil  -> {:reply, {:error, "You don't have a poll running."}, state}
      poll ->
        # create answer map
        answer_list = poll.answers |> Enum.reverse |> Enum.with_index
        answer_map  = for {el,idx} <- answer_list, into: %{} do
          {idx, %{votes: 0, text: el}}
        end

        # sum the votes into the answer map
        answer_map = List.foldl(Map.to_list(poll.votes), answer_map, fn ({user,vote}, state) ->
          vote_idx   = String.to_integer(vote) - 1
          case state[vote_idx] do
            nil -> 
              Logger.warn "!!! vote for unknown option !!!"
              state

            vote -> 
              new_answer = Map.put(state[vote_idx], :votes, state[vote_idx][:votes] + 1)
              Map.put(state, vote_idx, new_answer)
          end
        end)


        {:reply, {:ok, poll, answer_map}, state}
    end
  end

  def handle_call({:add_answer, uid, resp}, _from, state) do
    case Map.get(state.polls, uid) do
      nil  -> {:reply, {:error, "You don't have a poll running."}, state}
      poll ->
        new_poll  = %{poll | answers: [resp | poll.answers]}
        new_state = %{state | polls: Map.put(state.polls, uid, new_poll)}
        
        {:reply, :ok, new_state}
    end
  end
end
