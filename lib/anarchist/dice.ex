defmodule Anarchist.Dice do
  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, nil, opts)
  end


  def handle_call({:roll, num, type}, _from, _state) do
    # parse input ... 
    num  = String.to_integer(num)
    type = String.to_integer(type)

    if type > 100 or num > 50 do
      {:reply, "Oh fuck off, I'm not rolling that many dice.", nil}
    else
      rolls = for _die <- 1..num, do: :rand.uniform(type)
      rolls = inspect(rolls, char_lists: false)
      |> String.replace("[", "\\[")
          
      {:reply, "You rolled: #{rolls}", nil}
    end
  end
end
