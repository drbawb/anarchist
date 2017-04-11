defmodule Anarchist.Tag do
  use Ecto.Schema

  schema "tags" do
    field :schema, :string
    field :name,   :string
  end
end
