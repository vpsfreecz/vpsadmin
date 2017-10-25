defmodule VpsAdmin.Cluster.ResourceLockTest do
  use ExUnit.Case, async: true

  alias VpsAdmin.Cluster.Transaction
  alias VpsAdmin.Cluster.Transaction.Chain
  alias VpsAdmin.Persistence
  alias VpsAdmin.Persistence.Schema

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Persistence.Repo)
  end

  describe "hierarchy" do
    test "objects lock their parents inclusively" do
      location = %Schema.Location{
        label: "Test",
        domain: "test",
        row_state: :confirmed,
      } |> Persistence.Repo.insert!()
      node = %Schema.Node{
        name: "node1",
        location: location,
        ip_addr: "1.2.3.4",
        row_state: :confirmed,
      } |> Persistence.Repo.insert!()

      {:ok, chain} = Chain.stage_single(Transaction.Custom, fn ctx ->
        import Transaction

        ctx
        |> lock(node)
      end)

      locks = Persistence.Transaction.Chain.locks(chain)

      assert length(locks) == 3
      assert Enum.find(locks, false, &(&1.resource == "Elixir.VpsAdmin.Persistence.Schema.Node"))
      assert Enum.find(locks, false, &(&1.resource == "Elixir.VpsAdmin.Persistence.Schema.Location"))
      assert Enum.find(locks, false, &(&1.resource == "Elixir.VpsAdmin.Persistence.Schema.Cluster"))
    end
  end

  describe "inclusive locks" do
    test "multiple transactions can lock a single object" do
      location = %Schema.Location{
        label: "Test",
        domain: "test",
        row_state: :confirmed,
      } |> Persistence.Repo.insert!()

      for _x <- 0..10 do
        {:ok, _chain} = Chain.stage_single(Transaction.Custom, fn ctx ->
          import Transaction

          ctx
          |> lock(location, :inclusive)
        end)
      end
    end

    test "can be upgraded to exclusive lock" do
      loc1 = %Schema.Location{
        label: "Test",
        domain: "test",
        row_state: :confirmed,
      } |> Persistence.Repo.insert!()
      loc2 = %Schema.Location{
        label: "Test",
        domain: "test",
        row_state: :confirmed,
      } |> Persistence.Repo.insert!()

      {:ok, _chain} = Chain.stage_single(Transaction.Custom, fn ctx ->
        import Transaction

        ctx
        |> lock(loc1, :inclusive)
        |> lock(loc1, :exclusive)
        |> lock(loc2, :inclusive)
      end)

      {:error, _error} = Chain.stage_single(Transaction.Custom, fn ctx ->
        import Transaction

        assert_raise(Ecto.InvalidChangesetError, fn ->
          ctx
          |> lock(loc2, :exclusive)
        end)

        ctx
      end)
    end
  end

  describe "exclusive locks" do
    test "only one transaction can lock a single object" do
      location = %Schema.Location{
        label: "Test",
        domain: "test",
        row_state: :confirmed,
      } |> Persistence.Repo.insert!()

      {:ok, _chain} = Chain.stage_single(Transaction.Custom, fn ctx ->
        import Transaction

        ctx
        |> lock(location, :exclusive)
      end)

      {:error, _error} = Chain.stage_single(Transaction.Custom, fn ctx ->
        import Transaction

        assert_raise(Ecto.InvalidChangesetError, fn ->
          ctx
          |> lock(location, :exclusive)
        end)

        ctx
      end)
    end

    test "prevents inclusive locks by other transactions" do
      location = %Schema.Location{
        label: "Test",
        domain: "test",
        row_state: :confirmed,
      } |> Persistence.Repo.insert!()

      {:ok, _chain} = Chain.stage_single(Transaction.Custom, fn ctx ->
        import Transaction

        ctx
        |> lock(location, :exclusive)
      end)

      {:error, _error} = Chain.stage_single(Transaction.Custom, fn ctx ->
        import Transaction

        assert_raise(Ecto.InvalidChangesetError, fn ->
          ctx
          |> lock(location, :inclusive)
        end)

        ctx
      end)
    end

    test "is the default lock mode" do
      location = %Schema.Location{
        label: "Test",
        domain: "test",
        row_state: :confirmed,
      } |> Persistence.Repo.insert!()

      {:ok, chain} = Chain.stage_single(Transaction.Custom, fn ctx ->
        import Transaction

        ctx
        |> lock(location)
      end)

      locks = Persistence.Transaction.Chain.locks(chain)
      location_lock = Enum.find(
        locks,
        false,
        &(&1.resource == "Elixir.VpsAdmin.Persistence.Schema.Location")
      )

      assert length(locks) == 2
      assert location_lock
      assert location_lock.type == :exclusive
    end
  end

  describe "lock releasing" do
    test "can release all inclusive and exclusive locks" do
      loc1 = %Schema.Location{
        label: "Test",
        domain: "test",
        row_state: :confirmed,
      } |> Persistence.Repo.insert!()
      loc2 = %Schema.Location{
        label: "Test",
        domain: "test",
        row_state: :confirmed,
      } |> Persistence.Repo.insert!()

      {:ok, chain} = Chain.stage_single(Transaction.Custom, fn ctx ->
        import Transaction

        ctx
        |> lock(loc1, :inclusive)
        |> lock(loc2, :exclusive)
      end)

      locks = Persistence.Transaction.Chain.locks(chain)
      assert length(locks) == 3

      {:ok, chain} = Chain.close(chain, :ok)

      locks = Persistence.Transaction.Chain.locks(chain)
      assert length(locks) == 0
    end

    test "does not remove the inclusive locks if other transactions still hold it" do
      location = %Schema.Location{
        label: "Test",
        domain: "test",
        row_state: :confirmed,
      } |> Persistence.Repo.insert!()

      {:ok, chain1} = Chain.stage_single(Transaction.Custom, fn ctx ->
        import Transaction

        ctx
        |> lock(location, :inclusive)
      end)

      {:ok, chain2} = Chain.stage_single(Transaction.Custom, fn ctx ->
        import Transaction

        ctx
        |> lock(location, :inclusive)
      end)

      locks1 = Persistence.Transaction.Chain.locks(chain1)
      locks2 = Persistence.Transaction.Chain.locks(chain2)
      assert length(locks1) == 2
      assert length(locks2) == 2

      {:ok, chain1} = Chain.close(chain1, :ok)

      locks1 = Persistence.Transaction.Chain.locks(chain1)
      locks2 = Persistence.Transaction.Chain.locks(chain2)
      assert length(locks1) == 0
      assert length(locks2) == 2
    end
  end
end
