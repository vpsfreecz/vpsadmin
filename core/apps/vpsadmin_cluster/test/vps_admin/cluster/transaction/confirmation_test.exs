defmodule VpsAdmin.Cluster.Transaction.ConfirmationTest do
  use ExUnit.Case, async: true

  alias VpsAdmin.Cluster
  alias VpsAdmin.Cluster.{Command, Transaction, Query, Schema}
  alias VpsAdmin.Cluster.Transaction.Chain

  defmodule TestCommand do
    use Command

    def create(ctx, _opts), do: ctx
  end

  defmodule TestTransaction do
    use Transaction

    def label(), do: "Test transaction"

    def create(ctx, fun), do: fun.(ctx)
  end

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Cluster.Repo)
  end

  test "insert accepts a new changeset or schema" do
    import Cluster.Transaction
    import Cluster.Transaction.Confirmation

    {:ok, _chain} = Chain.single(Transaction.Custom, fn ctx ->
      ctx
      |> append(TestCommand, [], fn ctx ->
          {ctx, location} = insert(ctx, %Schema.Location{label: "Test", domain: "test"})
          assert is_integer(location.id)
          assert location.row_state == :new

          {ctx, location} = insert(
            ctx,
            %Schema.Location{} |> Ecto.Changeset.change(%{label: "Test", domain: "test"})
          )
          assert is_integer(location.id)
          assert location.row_state == :new

          ctx
        end)
    end)
  end

  test "insert accepts precreated changeset or schema" do
    import Cluster.Transaction
    import Cluster.Transaction.Confirmation

    {:ok, _chain} = Chain.single(Transaction.Custom, fn ctx ->
      new_location = Cluster.Repo.insert!(%Schema.Location{label: "Test", domain: "test"})

      ctx
      |> append(TestCommand, [], fn ctx ->
          {ctx, location} = insert(ctx, new_location)
          assert is_integer(location.id)
          assert new_location.id == location.id
          assert location.row_state == :new

          {ctx, location} = insert(
            ctx,
            new_location |> Ecto.Changeset.change()
          )
          assert is_integer(location.id)
          assert new_location.id == location.id
          assert location.row_state == :new

          ctx
        end)
    end)
  end

  test "delete accepts changeset or schema" do
    import Cluster.Transaction
    import Cluster.Transaction.Confirmation

    {:ok, _chain} = Chain.single(Transaction.Custom, fn ctx ->
      orig_location = Cluster.Repo.insert!(%Schema.Location{label: "Test", domain: "test"})

      ctx
      |> append(TestCommand, [], fn ctx ->
          {ctx, location} = delete(ctx, orig_location)
          assert is_integer(location.id)
          assert location.row_state == :deleted

          {ctx, location} = delete(
            ctx,
            orig_location |> Ecto.Changeset.change()
          )
          assert is_integer(location.id)
          assert location.row_state == :deleted

          ctx
        end)
    end)
  end

  test "change accepts changeset or schema" do
    import Cluster.Transaction
    import Cluster.Transaction.Confirmation

    {:ok, _chain} = Chain.single(Transaction.Custom, fn ctx ->
      orig_location = Cluster.Repo.insert!(%Schema.Location{label: "Test", domain: "test"})

      ctx
      |> append(TestCommand, [], fn ctx ->
          {ctx, location} = change(ctx, orig_location, %{label: "Better Test"})
          assert is_integer(location.id)
          assert orig_location.id == location.id
          assert location.label == "Test"
          assert location.row_state == :updated
          assert location.row_changes == %{label: "Better Test"}

          {ctx, location} = change(
            ctx,
            orig_location |> Ecto.Changeset.change(),
            %{label: "Best Test"}
          )
          assert is_integer(location.id)
          assert orig_location.id == location.id
          assert location.label == "Test"
          assert location.row_state == :updated
          assert location.row_changes == %{label: "Best Test"}

          ctx
        end)
    end)
  end

  test "changing inserted rows" do
    import Cluster.Transaction
    import Cluster.Transaction.Confirmation

    {:ok, _chain} = Chain.single(Transaction.Custom, fn ctx ->
      ctx
      |> append(TestCommand, [], fn ctx ->
          {ctx, location} = insert(ctx, %Schema.Location{label: "Test", domain: "test"})
          assert is_integer(location.id)
          assert location.row_state == :new

          {ctx, location} = change(ctx, location, %{label: "Just Test"})
          assert is_integer(location.id)
          assert location.row_state == :new
          assert location.row_changes == %{label: "Just Test"}
          assert location.label == "Test"

          ctx
        end)
    end)
  end

  test "deleting inserted rows" do
    import Cluster.Transaction
    import Cluster.Transaction.Confirmation

    {:ok, _chain} = Chain.single(Transaction.Custom, fn ctx ->
      ctx
      |> append(TestCommand, [], fn ctx ->
          {ctx, location} = insert(ctx, %Schema.Location{label: "Test", domain: "test"})
          assert is_integer(location.id)
          assert location.row_state == :new

          {ctx, location} = delete(ctx, location)
          assert is_integer(location.id)
          assert location.row_state == :deleted

          ctx
        end)
    end)
  end

  test "can confirm changes" do
    import Cluster.Transaction
    import Cluster.Transaction.Confirmation

    {:ok, pid} = Agent.start_link(fn -> nil end)

    {:ok, chain} = Chain.single(Transaction.Custom, fn ctx ->
      loc1 = Cluster.Repo.insert!(%Schema.Location{label: "Test1", domain: "test1"})
      loc2 = Cluster.Repo.insert!(%Schema.Location{label: "Test2", domain: "test2"})
      loc3 = Cluster.Repo.insert!(%Schema.Location{label: "Test3", domain: "test3"})

      Agent.update(pid, fn _ -> %{loc1: loc1.id, loc2: loc2.id, loc3: loc3.id} end)

      ctx
      |> append(TestCommand, [], fn ctx ->
          {ctx, _loc1} = insert(ctx, loc1)
          {ctx, _loc2} = change(ctx, loc2, %{label: "Better Test 2", domain: "better.test2"})
          {ctx, _loc3} = delete(ctx, loc3)

          ctx
        end)
    end)

    {:ok, _chain} = Chain.close(chain, :ok)
    state = Agent.get(pid, fn state -> state end)

    loc1 = Cluster.Repo.get(Schema.Location, state.loc1)
    loc2 = Cluster.Repo.get(Schema.Location, state.loc2)
    loc3 = Cluster.Repo.get(Schema.Location, state.loc3)

    assert loc1
    assert loc1.row_state == :confirmed

    assert loc2
    assert loc2.row_state == :confirmed
    assert is_nil(loc2.row_changes)
    assert loc2.label == "Better Test 2"
    assert loc2.domain == "better.test2"

    refute loc3

    Agent.stop(pid)

    confirmations = Query.Transaction.Confirmation.for_chain(chain)
    assert length(confirmations) > 0

    for cnf <- confirmations do
      assert cnf.state == :confirmed
    end
  end

  test "can discard changes" do
    import Cluster.Transaction
    import Cluster.Transaction.Confirmation

    {:ok, pid} = Agent.start_link(fn -> nil end)

    {:ok, chain} = Chain.single(Transaction.Custom, fn ctx ->
      loc1 = Cluster.Repo.insert!(%Schema.Location{label: "Test1", domain: "test1"})
      loc2 = Cluster.Repo.insert!(%Schema.Location{label: "Test2", domain: "test2"})
      loc3 = Cluster.Repo.insert!(%Schema.Location{label: "Test3", domain: "test3"})

      Agent.update(pid, fn _ -> %{loc1: loc1.id, loc2: loc2.id, loc3: loc3.id} end)

      ctx
      |> append(TestCommand, [], fn ctx ->
          {ctx, _loc1} = insert(ctx, loc1)
          {ctx, _loc2} = change(ctx, loc2, %{label: "Better Test 2", domain: "better.test2"})
          {ctx, _loc3} = delete(ctx, loc3)

          ctx
        end)
    end)

    {:ok, _chain} = Chain.close(chain, :error)
    state = Agent.get(pid, fn state -> state end)

    loc1 = Cluster.Repo.get(Schema.Location, state.loc1)
    loc2 = Cluster.Repo.get(Schema.Location, state.loc2)
    loc3 = Cluster.Repo.get(Schema.Location, state.loc3)

    refute loc1

    assert loc2
    assert loc2.row_state == :confirmed
    assert is_nil(loc2.row_changes)
    assert loc2.label == "Test2"
    assert loc2.domain == "test2"

    assert loc3
    assert loc3.row_state == :confirmed

    Agent.stop(pid)

    confirmations = Query.Transaction.Confirmation.for_chain(chain)
    assert length(confirmations) > 0

    for cnf <- confirmations do
      assert cnf.state == :discarded
    end
  end
end
