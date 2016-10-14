defmodule Anarchist.Telegram do
  require Logger

  @moduledoc """
  The Telegram Bot API endpoint.
  """

  def start_link(opts \\ []) do
    Logger.info "telegram starting up ..."
    Logger.info "i am the walrus: #{inspect Yocingo.get_me}"

    pid = spawn_link(fn -> main_loop(0) end)
    {:ok, pid}
  end

  def main_loop(last_update) do
    
  # TODO: yocingo shouldn't match error, but it does !!!
    try do
      updates = Yocingo.get_updates(last_update)
      process_updates(updates)
      main_loop(last_update_from(updates) + 1)
    rescue
      e in MatchError -> main_loop(last_update)
    end

  end

  # dispatches updates to handlers
  defp process_updates(updates) do
    results = updates["result"]
    Logger.info "got #{Enum.count results} updates"

    for update <- results do
      message   = update["message"]
      room_id   = message["chat"]["id"]
      text      = message["text"]

      Logger.debug "telegram :: #{inspect message}"
      Logger.debug "telegram :: #{room_id} :: #{inspect text}"
      dispatch(room_id, text)
    end
  end

  # grabs the largsest update id we've seen in this batch
  defp last_update_from(updates) do
    results = updates["result"]
    List.foldl(results, 0, fn el,acc -> max(acc, el["update_id"]) end)
  end

  # dispatch an incoming chat message to appropriate bot module
  defp dispatch(room_id, text) do
    case text do
      "!catfact" ->
        factoid = GenServer.call CatFacts, :fact
        Yocingo.send_message(room_id, factoid)

      text when not is_nil(text) -> process_text(room_id, text)
      _ -> Logger.warn "bot could not dispatch message"
    end
  end

  # fall-through handler for plaintext
  # stores shouts in the shout db, otherwise does nothing
  defp process_text(room_id, text) do
    if String.upcase(text) == text do
      Logger.debug "user shouted at me ..."
      random = GenServer.call(Shouter, :random)
      store  = GenServer.call(Shouter, {:add, text})

      Yocingo.send_message(room_id, random)
    end
  end
end
