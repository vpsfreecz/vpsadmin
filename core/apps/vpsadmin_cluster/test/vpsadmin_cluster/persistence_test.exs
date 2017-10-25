defmodule VpsAdmin.Cluster.PersistenceTest do
  use ExUnit.Case, async: true

  alias VpsAdmin.Cluster.{Command, Transaction}
  alias VpsAdmin.Cluster.Transaction.Chain
  alias VpsAdmin.Persistence
  alias VpsAdmin.Persistence.Schema

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Persistence.Repo)
  end

  test "access new and confirmed data" do
    {:ok, pid} = Agent.start_link(fn -> nil end)

    {:ok, chain} = Chain.stage_single(Transaction.Custom, fn ctx ->
      import Transaction
      import Transaction.Confirmation

      ctx
      |> append(Command.Test.Noop, [], fn ctx ->
           {ctx, location} = insert(ctx, %Schema.Location{label: "Test", domain: "test"})
           Agent.update(pid, fn _ -> location.id end)
           ctx
         end)
    end)

    location_id = Agent.get(pid, fn state -> state end)

    assert Persistence.scoped_get(Schema.Location, location_id, chain)
    refute Persistence.scoped_get(Schema.Location, location_id, :confirmed)

    Agent.stop(pid)
  end

  test "access updated and confirmed data" do
    orig_location = %Schema.Location{
      label: "Test",
      domain: "test",
      row_state: :confirmed,
    } |> Persistence.Repo.insert!()

    {:ok, chain} = Chain.stage_single(Transaction.Custom, fn ctx ->
      import Transaction
      import Transaction.Confirmation

      ctx
      |> append(Command.Test.Noop, [], fn ctx ->
           {ctx, _location} = change(ctx, orig_location, %{label: "Super Test"})
           ctx
         end)
    end)

    location = Persistence.scoped_get(Schema.Location, orig_location.id, chain)

    assert location.row_state == :updated
    assert location.label == "Super Test"

    location = Persistence.scoped_get(Schema.Location, orig_location.id, :confirmed)

    assert location.row_state == :updated
    assert location.label == "Test"
  end

  test "access updated data when changes are by multiple chains" do
    orig_location = %Schema.Location{
      label: "Test",
      domain: "test",
      row_state: :confirmed,
    } |> Persistence.Repo.insert!()

    {:ok, chain1} = Chain.stage_single(Transaction.Custom, fn ctx ->
      import Transaction
      import Transaction.Confirmation

      ctx
      |> append(Command.Test.Noop, [], fn ctx ->
           {ctx, _location} = change(ctx, orig_location, %{label: "Super Test"})
           ctx
         end)
    end)

    orig_location = Persistence.Repo.get(Schema.Location, orig_location.id)

    {:ok, chain2} = Chain.stage_single(Transaction.Custom, fn ctx ->
      import Transaction
      import Transaction.Confirmation

      ctx
      |> append(Command.Test.Noop, [], fn ctx ->
           {ctx, _location} = change(ctx, orig_location, %{domain: "megatest"})
           ctx
         end)
    end)

    location = Persistence.scoped_get(Schema.Location, orig_location.id, chain1)

    assert location.row_state == :updated
    assert location.label == "Super Test"
    assert location.domain == "test"

    location = Persistence.scoped_get(Schema.Location, orig_location.id, chain2)

    assert location.row_state == :updated
    assert location.label == "Test"
    assert location.domain == "megatest"

    location = Persistence.scoped_get(Schema.Location, orig_location.id, :confirmed)

    assert location.row_state == :updated
    assert location.label == "Test"
    assert location.domain == "test"
  end

  test "access deleted and confirmed data" do
    orig_location = %Persistence.Schema.Location{
      label: "Test",
      domain: "test",
      row_state: :confirmed,
    } |> Persistence.Repo.insert!()

    {:ok, chain} = Chain.stage_single(Transaction.Custom, fn ctx ->
      import Transaction
      import Transaction.Confirmation

      ctx
      |> append(Command.Test.Noop, [], fn ctx ->
           {ctx, _location} = delete(ctx, orig_location)
           ctx
         end)
    end)

    refute Persistence.scoped_get(Schema.Location, orig_location.id, chain)

    location = Persistence.scoped_get(Schema.Location, orig_location.id, :confirmed)
    assert location
    assert location.row_state == :deleted
  end

  test "preloading of confirmed and changed associations" do
    loc1 = %Schema.Location{
      label: "Test 1",
      domain: "test1",
      row_state: :confirmed,
    } |> Persistence.Repo.insert!()

    loc2 = %Schema.Location{
      label: "Test 2",
      domain: "test2",
      row_state: :confirmed,
    } |> Persistence.Repo.insert!()

    node = %Schema.Node{
      name: "node1",
      ip_addr: "1.2.3.4",
      location: loc1,
    } |> Persistence.Repo.insert!()

    {:ok, chain} = Chain.stage_single(Transaction.Custom, fn ctx ->
      import Transaction
      import Transaction.Confirmation

      ctx
      |> append(Command.Test.Noop, [], fn ctx ->
           {ctx, _} = change(ctx, node, %{location_id: loc2.id})
           ctx
         end)
    end)

    node = Schema.Node
      |> Persistence.scoped_get(node.id, chain)
      |> Persistence.preload(:location)

    assert node.location.id == loc2.id

    node = Schema.Node
      |> Persistence.scoped_get(node.id, :confirmed)
      |> Persistence.preload(:location)

    assert node.location.id == loc1.id
  end

  test "auto-scoping processes running a transaction" do
    {:ok, pid} = Agent.start_link(fn -> nil end)

    orig_loc1 = %Schema.Location{
      label: "Test 1",
      domain: "test1",
      row_state: :confirmed,
    } |> Persistence.Repo.insert!()

    orig_loc2 = %Schema.Location{
      label: "Test 2",
      domain: "test2",
      row_state: :confirmed,
    } |> Persistence.Repo.insert!()

    {:ok, _chain} = Chain.stage_single(Transaction.Custom, fn ctx ->
      import Transaction
      import Transaction.Confirmation

      ctx
      |> append(Command.Test.Noop, [], fn ctx ->
           # Change
           {ctx, _location} = change(ctx, orig_loc1, %{label: "Super Test"})

           location = Persistence.get(Schema.Location, orig_loc1.id)

           assert location.row_state == :updated
           assert location.label == "Super Test"

           # Insert
           {ctx, location} = insert(ctx, %Schema.Location{label: "New", domain: "new"})
           Agent.update(pid, fn _ -> location.id end)
           assert Persistence.get(Schema.Location, location.id)

           # Delete
           assert Persistence.get(Schema.Location, orig_loc2.id)
           {ctx, _location} = delete(ctx, orig_loc2)
           refute Persistence.get(Schema.Location, orig_loc2.id)

           ctx
         end)
    end)

    # Change
    location = Persistence.get(Schema.Location, orig_loc1.id)

    assert location.row_state == :updated
    assert location.label == "Test 1"

    # Insert
    refute Persistence.get(Schema.Location, Agent.get(pid, fn state -> state end))

    # Delete
    location = Persistence.get(Schema.Location, orig_loc2.id)

    assert location.row_state == :deleted
    assert location.label == "Test 2"
  end
end
