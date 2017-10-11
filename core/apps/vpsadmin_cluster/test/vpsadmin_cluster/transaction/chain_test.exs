defmodule VpsAdmin.Cluster.Transaction.ChainTest do
  use ExUnit.Case, async: true

  alias VpsAdmin.Cluster
  alias VpsAdmin.Cluster.{Command, Transaction}
  alias VpsAdmin.Cluster.Transaction.Chain
  alias VpsAdmin.Persistence
  alias VpsAdmin.Persistence.Schema

  defmodule SimpleCommand do
    use Command

    def create(ctx, _opts), do: ctx
  end

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
      |> append(SimpleCommand)
      |> append(SimpleCommand)
      |> append(SimpleCommand)
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
      |> append(SimpleCommand, [], fn ctx ->
           {ctx, location} = insert(ctx, %Schema.Location{label: "Test", domain: "test"})
           Context.put(ctx, :loc1, location)
         end)
      |> append(SimpleCommand, [], fn ctx ->
           {ctx, location} = insert(ctx, %Schema.Location{label: "Test", domain: "test"})
           Context.put(ctx, :loc2, location)
         end)
      |> append(SimpleCommand, [], fn ctx ->
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

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Persistence.Repo)
  end

  test "can create an empty chain" do
    assert is_integer(Chain.create.id)
  end

  test "can create a chain with a single transaction" do
    {:ok, chain} = Chain.single(Full)
    assert is_integer(chain.id)
    assert chain.state == :running
  end

  test "can create a chain with a single transaction with options" do
    {:ok, pid} = Agent.start_link(fn -> nil end)
    {:ok, _chain} = Chain.single(WithOptions, agent: pid, value: 123)
    assert Agent.get(pid, fn state -> state end) == 123
    Agent.stop(pid)
  end

  test "can create a custom chain" do
    {:ok, chain} = Chain.custom(fn chain ->
      import Chain, only: [append: 2]

      chain
      |> append(Empty)
      |> append(Full)
    end)

    assert is_integer(chain.id)
    assert chain.state == :running
  end

  test "can pass options to transactions via append" do
    {:ok, pid1} = Agent.start_link(fn -> nil end)
    {:ok, pid2} = Agent.start_link(fn -> nil end)

    {:ok, chain} = Chain.custom(fn chain ->
      import Chain, only: [append: 3]

      chain
      |> append(WithOptions, agent: pid1, value: 456)
      |> append(WithOptions, agent: pid2, value: 789)
    end)

    assert is_integer(chain.id)
    assert chain.state == :running
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
    {:ok, chain} = Chain.single(WithChanges, pid)
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
    {:ok, chain} = Chain.single(WithChanges, pid)
    {:ok, chain} = Chain.close(chain, :error)

    data = Agent.get(pid, fn state -> state end)

    assert chain.state == :failed
    assert Persistence.Transaction.Chain.locks(chain) == []
    refute Persistence.get(Schema.Location, data.loc1)
    refute Persistence.get(Schema.Location, data.loc2)
    refute Persistence.get(Schema.Location, data.loc3)
  end
end
