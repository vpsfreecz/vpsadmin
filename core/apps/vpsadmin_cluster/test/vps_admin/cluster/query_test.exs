defmodule VpsAdmin.Cluster.QueryTest do
  use ExUnit.Case, async: true

  alias VpsAdmin.Cluster
  alias VpsAdmin.Cluster.{Command, Query, Schema, Transaction}
  alias VpsAdmin.Cluster.Transaction.Chain

  defmodule SimpleCommand do
    use Command

    def create(ctx, _opts), do: ctx
  end

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Cluster.Repo)
  end

  test "access new and confirmed data" do
    {:ok, pid} = Agent.start_link(fn -> nil end)

    {:ok, chain} = Chain.single(Transaction.Custom, fn ctx ->
      import Transaction
      import Transaction.Confirmation

      ctx
      |> append(SimpleCommand, [], fn ctx ->
           {ctx, location} = insert(ctx, %Schema.Location{label: "Test", domain: "test"})
           Agent.update(pid, fn _ -> location.id end)
           ctx
         end)
    end)

    location_id = Agent.get(pid, fn state -> state end)

    assert Query.scoped_get(Schema.Location, location_id, chain)
    refute Query.scoped_get(Schema.Location, location_id, :confirmed)

    Agent.stop(pid)
  end

  test "access updated and confirmed data" do
    orig_location = %Schema.Location{
      label: "Test",
      domain: "test",
      row_state: :confirmed,
    } |> Cluster.Repo.insert!()

    {:ok, chain} = Chain.single(Transaction.Custom, fn ctx ->
      import Transaction
      import Transaction.Confirmation

      ctx
      |> append(SimpleCommand, [], fn ctx ->
           {ctx, _location} = change(ctx, orig_location, %{label: "Super Test"})
           ctx
         end)
    end)

    location = Query.scoped_get(Schema.Location, orig_location.id, chain)

    assert location.row_state == :updated
    assert location.label == "Super Test"

    location = Query.scoped_get(Schema.Location, orig_location.id, :confirmed)

    assert location.row_state == :updated
    assert location.label == "Test"
  end

  test "access deleted and confirmed data" do
    orig_location = %Cluster.Schema.Location{
      label: "Test",
      domain: "test",
      row_state: :confirmed,
    } |> Cluster.Repo.insert!()

    {:ok, chain} = Chain.single(Transaction.Custom, fn ctx ->
      import Transaction
      import Transaction.Confirmation

      ctx
      |> append(SimpleCommand, [], fn ctx ->
           {ctx, _location} = delete(ctx, orig_location)
           ctx
         end)
    end)

    refute Query.scoped_get(Schema.Location, orig_location.id, chain)

    location = Query.scoped_get(Schema.Location, orig_location.id, :confirmed)
    assert location
    assert location.row_state == :deleted
  end

  test "preloading of confirmed and changed associations" do
    loc1 = %Schema.Location{
      label: "Test 1",
      domain: "test1",
      row_state: :confirmed,
    } |> Cluster.Repo.insert!()

    loc2 = %Schema.Location{
      label: "Test 2",
      domain: "test2",
      row_state: :confirmed,
    } |> Cluster.Repo.insert!()

    node = %Schema.Node{
      name: "node1",
      ip_addr: "1.2.3.4",
      location: loc1,
    } |> Cluster.Repo.insert!()

    {:ok, chain} = Chain.single(Transaction.Custom, fn ctx ->
      import Transaction
      import Transaction.Confirmation

      ctx
      |> append(SimpleCommand, [], fn ctx ->
           {ctx, _} = change(ctx, node, %{location_id: loc2.id})
           ctx
         end)
    end)

    node = Schema.Node
      |> Query.scoped_get(node.id, chain)
      |> Query.preload(:location)

    assert node.location.id == loc2.id

    node = Schema.Node
      |> Query.scoped_get(node.id, :confirmed)
      |> Query.preload(:location)

    assert node.location.id == loc1.id
  end

  test "auto-scoping processes running a transaction" do
    {:ok, pid} = Agent.start_link(fn -> nil end)

    orig_loc1 = %Schema.Location{
      label: "Test 1",
      domain: "test1",
      row_state: :confirmed,
    } |> Cluster.Repo.insert!()

    orig_loc2 = %Schema.Location{
      label: "Test 2",
      domain: "test2",
      row_state: :confirmed,
    } |> Cluster.Repo.insert!()

    {:ok, _chain} = Chain.single(Transaction.Custom, fn ctx ->
      import Transaction
      import Transaction.Confirmation

      ctx
      |> append(SimpleCommand, [], fn ctx ->
           # Change
           {ctx, _location} = change(ctx, orig_loc1, %{label: "Super Test"})

           location = Query.get(Schema.Location, orig_loc1.id)

           assert location.row_state == :updated
           assert location.label == "Super Test"

           # Insert
           {ctx, location} = insert(ctx, %Schema.Location{label: "New", domain: "new"})
           Agent.update(pid, fn _ -> location.id end)
           assert Query.get(Schema.Location, location.id)

           # Delete
           assert Query.get(Schema.Location, orig_loc2.id)
           {ctx, _location} = delete(ctx, orig_loc2)
           refute Query.get(Schema.Location, orig_loc2.id)

           ctx
         end)
    end)

    # Change
    location = Query.get(Schema.Location, orig_loc1.id)

    assert location.row_state == :updated
    assert location.label == "Test 1"

    # Insert
    refute Query.get(Schema.Location, Agent.get(pid, fn state -> state end))

    # Delete
    location = Query.get(Schema.Location, orig_loc2.id)

    assert location.row_state == :deleted
    assert location.label == "Test 2"
  end
end
