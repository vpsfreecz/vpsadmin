defmodule VpsAdmin.Persistence.Lockable do
  @callback lock_parent(map, :inclusive | :exclusive) :: any

  def get_entities(struct, type) do
    _get_entities(struct, type, [{struct, type}])
  end

  defp _get_entities(struct, type, locks) do
    case apply(struct.__struct__, :lock_parent, [struct, type]) do
      nil ->
        locks
      {parent, t} ->
        _get_entities(parent, t, [{parent, t} | locks])
    end
  end
end
