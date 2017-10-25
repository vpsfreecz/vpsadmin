defmodule VpsAdmin.Cluster.Transaction.ChainTest do
  use ExUnit.Case, async: true

  alias VpsAdmin.Cluster
  alias VpsAdmin.Cluster.{Command, Transaction}
  alias VpsAdmin.Cluster.Transaction.Chain
  alias VpsAdmin.Persistence
  alias VpsAdmin.Persistence.{Factory, Schema}

  defmodule Empty do
    use Transaction

    def label(), do: "Empty"

    def create(ctx, _opts), do: ctx
  end

  defmodule Full do
    use Transaction

    def label(), do: "Full"

    def create(ctx, _opts) do
      ctx
      |> append(Cluster.Command.Test.Noop)
      |> append(Cluster.Command.Test.Noop)
      |> append(Cluster.Command.Test.Noop)
    end
  end

  defmodule WithOptions do
    use Transaction

    def label(), do: "With options"

    def create(ctx, [agent: pid, value: v]) do
      :ok = Agent.update(pid, fn _state -> v end)
      ctx
    end
  end

  defmodule WithChanges do
    use Transaction

    def label(), do: "With changes"

    def create(ctx, pid) do
      ctx
      |> append(Cluster.Command.Test.Noop, [], fn ctx ->
           {ctx, location} = insert(ctx, %Schema.Location{label: "Test", domain: "test"})
           Context.put(ctx, :loc1, location)
         end)
      |> append(Cluster.Command.Test.Noop, [], fn ctx ->
           {ctx, location} = insert(ctx, %Schema.Location{label: "Test", domain: "test"})
           Context.put(ctx, :loc2, location)
         end)
      |> append(Cluster.Command.Test.Noop, [], fn ctx ->
           {ctx, location} = insert(ctx, %Schema.Location{label: "Test", domain: "test"})
           Context.put(ctx, :loc3, location)
         end)
      |> lock(&(&1.data.loc1))
      |> lock(&(&1.data.loc2))
      |> lock(&(&1.data.loc3))
      |> run(fn ctx ->
           Agent.update(pid, fn _ -> for {k,v} <- ctx.data, into: %{}, do: {k, v.id} end)
         end)
    end
  end

  defmodule WithNodes do
    use Transaction

    def label, do: "With nodes"

    def create(ctx, [node1, node2, node3]) do
      ctx
      |> append(Cluster.Command.Test.Noop, node1)
      |> append(Cluster.Command.Test.Noop, node2)
      |> append(Cluster.Command.Test.Noop, node2)
      |> append(Cluster.Command.Test.Noop, node3)
    end
  end

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Persistence.Repo)
  end

  test "can create an empty chain" do
    assert is_integer(Chain.create.id)
  end

  test "can create a chain with a single transaction" do
    {:ok, chain} = Chain.stage_single(Full)
    assert is_integer(chain.id)
    assert chain.state == :staged
  end

  test "can create a chain with a single transaction with options" do
    {:ok, pid} = Agent.start_link(fn -> nil end)
    {:ok, _chain} = Chain.stage_single(WithOptions, agent: pid, value: 123)
    assert Agent.get(pid, fn state -> state end) == 123
    Agent.stop(pid)
  end

  test "can create a custom chain" do
    {:ok, chain} = Chain.stage_custom(fn chain ->
      import Chain, only: [append: 2]

      chain
      |> append(Empty)
      |> append(Full)
    end)

    assert is_integer(chain.id)
    assert chain.state == :staged
  end

  test "can pass options to transactions via append" do
    {:ok, pid1} = Agent.start_link(fn -> nil end)
    {:ok, pid2} = Agent.start_link(fn -> nil end)

    {:ok, chain} = Chain.stage_custom(fn chain ->
      import Chain, only: [append: 3]

      chain
      |> append(WithOptions, agent: pid1, value: 456)
      |> append(WithOptions, agent: pid2, value: 789)
    end)

    assert is_integer(chain.id)
    assert chain.state == :staged
    assert Agent.get(pid1, fn state -> state end) == 456
    assert Agent.get(pid2, fn state -> state end) == 789

    Agent.stop(pid1)
    Agent.stop(pid2)
  end

  test "is staged by default" do
    assert Chain.create.state == :staged
  end

  test "can be closed on success" do
    {:ok, pid} = Agent.start_link(fn -> nil end)
    {:ok, chain} = Chain.stage_single(WithChanges, pid)
    {:ok, chain} = Chain.close(chain, :ok)

    data = Agent.get(pid, fn state -> state end)

    assert chain.state == :done
    assert Persistence.Transaction.Chain.locks(chain) == []
    assert Persistence.get(Schema.Location, data.loc1)
    assert Persistence.get(Schema.Location, data.loc2)
    assert Persistence.get(Schema.Location, data.loc3)
  end

  test "can be closed on error" do
    {:ok, pid} = Agent.start_link(fn -> nil end)
    {:ok, chain} = Chain.stage_single(WithChanges, pid)
    {:ok, chain} = Chain.close(chain, :error)

    data = Agent.get(pid, fn state -> state end)

    assert chain.state == :failed
    assert Persistence.Transaction.Chain.locks(chain) == []
    refute Persistence.get(Schema.Location, data.loc1)
    refute Persistence.get(Schema.Location, data.loc2)
    refute Persistence.get(Schema.Location, data.loc3)
  end

  test "returns involved nodes" do
    location = Factory.insert(:location)
    node1 = Factory.insert(:node, location: location)
    node2 = Factory.insert(:node, location: location)
    node3 = Factory.insert(:node, location: location)
    node4 = Factory.insert(:node, location: location)

    {:ok, chain} = Chain.stage_custom(fn chain ->
      import Chain, only: [append: 3]

      chain
      |> append(WithNodes, [node1, node2, node3])
    end)

    nodes = Persistence.Transaction.Chain.nodes(chain)

    assert length(nodes) == 3
    assert Enum.find(nodes, false, &(&1.id == node1.id))
    assert Enum.find(nodes, false, &(&1.id == node2.id))
    assert Enum.find(nodes, false, &(&1.id == node3.id))
    refute Enum.find(nodes, false, &(&1.id == node4.id))
  end
end
