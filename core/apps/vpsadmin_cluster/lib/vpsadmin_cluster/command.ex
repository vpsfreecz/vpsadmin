defmodule VpsAdmin.Cluster.Command do
  alias VpsAdmin.Cluster
  alias VpsAdmin.Cluster.Transaction.Context
  alias VpsAdmin.Persistence
  alias VpsAdmin.Persistence.Schema

  @callback create(ctx :: Context.t, args :: any) :: Context.t

  defmacro __using__([]) do
    quote do
      @behaviour unquote(__MODULE__)
      import unquote(__MODULE__), only: [node: 2, params: 2]
      alias VpsAdmin.Cluster
    end
  end

  def new(ctx) do
    %Schema.Command{
      transaction_id: ctx.transaction.id,
      transaction_confirmations: [],
    }
  end

  def create(ctx, cmd_mod, opts \\ [], fun \\ nil) do
    cmd = ctx
      |> new()
      |> Map.put(:module, to_string(cmd_mod))

    ctx
    |> Cluster.Transaction.Context.command(cmd)
    |> cmd_mod.create(opts)
    |> ensure_node()
    |> confirmations(fun)
  end

  def finalize(ctx) do
    ctx = update_in(ctx.command.transaction_confirmations, &Enum.reverse/1)
    Persistence.Command.create(ctx.command)
    ctx
  end

  @spec node(Context.t, struct | integer | :any) :: Context.t
  def node(ctx, id) when is_integer(id) do
    update_in(ctx.command.node_id, fn _ -> id end)
  end

  def node(ctx, %Schema.Node{} = node), do: node(ctx, node.id)

  def node(ctx, :any), do: node(Cluster.Node.self_id)

  @spec params(Context.t, map) :: Context.t
  def params(ctx, map) do
    update_in(ctx.command.params, fn _ -> map end)
  end

  def execute(cmd) do
    apply(Module.concat([cmd.module]), :execute, [cmd.params])
  end

  def rollback(cmd) do
    apply(Module.concat([cmd.module]), :rollback, [cmd.params])
  end

  defp confirmations(ctx, nil), do: ctx
  defp confirmations(ctx, fun), do: fun.(ctx)

  defp ensure_node(ctx) do
    update_in(ctx.command.node_id, fn
      nil -> Cluster.Node.self_id
      id -> id
    end)
  end
end
