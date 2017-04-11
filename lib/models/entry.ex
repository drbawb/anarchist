defmodule Anarchist.Entry do
  use Ecto.Schema

  schema "entries" do
    field :hash,      :string
    field :mime,      :string
    field :is_orphan, :boolean
  end
end
