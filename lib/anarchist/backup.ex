defmodule Anarchist.Backup do
  use GenServer

  @moduledoc "This task periodically dumps various module DBs to the disk."

  @work_timer 5 * 60 * 1000
  @tasks [
    [Shouter, {:persist, "db/shouts-auto.txt"}]]

  def start_link do
    GenServer.start_link(__MODULE__, %{})
  end

  def init(state) do
    GenServer.call Shouter, {:load, "db/shouts-auto.txt"}
    schedule_work()
    {:ok, state}
  end

  # does some work and goes back to sleep ...
  def handle_info(:work, state) do
    schedule_work()
    for [mod, task] <- @tasks, do: GenServer.call(mod, task)
    {:noreply, state}
  end

  # sleeps for `@work_timer` millis before sending a :work message
  defp schedule_work() do
    Process.send_after(self(), :work, @work_timer)
  end
end
