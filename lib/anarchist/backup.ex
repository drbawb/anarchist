defmodule Anarchist.Backup do
  use GenServer
  require Logger

  @moduledoc "This task periodically dumps various module DBs to the disk."

  @work_timer 5 * 60 * 1000
  @tasks [
    [Shouter, {:persist, "db/shouts-auto.txt"}]
  ]

  def start_link do
    GenServer.start_link(__MODULE__, %{})
  end

  def init(state) do
    schedule_work()
    {:ok, state}
  end

  # does some work and goes back to sleep ...
  def handle_info(:work, state) do
    Logger.info "performing backups..."

    for [mod, task] <- @tasks do
      GenServer.call(mod, task)
    end

    schedule_work()
    {:noreply, state}
  end

  # sleeps for `@work_timer` millis before sending a :work message
  defp schedule_work() do
    Process.send_after(self(), :work, @work_timer)
  end
end
