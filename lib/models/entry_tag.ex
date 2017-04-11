defmodule Anarchist.EntryTag do
  use Ecto.Schema

  schema "entries_tags" do
    field :entry_id, :integer
    field :tag_id, :integer
  end
end
