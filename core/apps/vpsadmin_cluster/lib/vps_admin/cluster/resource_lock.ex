defmodule VpsAdmin.Cluster.ResourceLock do
  def new(ctx, schema) do
    %{
      resource: Atom.to_string(schema.__struct__),
      resource_id: primary_keys(schema.__struct__, Map.from_struct(schema)),
      transaction_chain_id: ctx.chain.id,
    }
  end

  defp primary_keys(schema, data) do
    for pk <- schema.__schema__(:primary_key), into: %{} do
      {pk, data[pk]}
    end
  end
end
