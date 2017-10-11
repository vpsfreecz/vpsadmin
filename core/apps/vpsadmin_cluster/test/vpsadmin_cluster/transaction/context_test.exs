defmodule VpsAdmin.Cluster.Transaction.ContextTest do
  use ExUnit.Case, async: true

  alias VpsAdmin.Cluster.Transaction.Context

  test "context creation" do
    ctx = Context.new(:chain)

    assert ctx.chain == :chain
    assert is_nil(ctx.transaction)
    assert is_nil(ctx.command)
    assert ctx.locks == []
    assert ctx.data == %{}
  end

  test "scope to transaction" do
    ctx = Context.new(:chain)
      |> Context.transaction(:trans)

    assert ctx.chain == :chain
    assert ctx.transaction == :trans
    assert is_nil(ctx.command)
  end

  test "scope to command" do
    ctx = Context.new(:chain)
      |> Context.transaction(:trans)
      |> Context.command(:cmd)

    assert ctx.chain == :chain
    assert ctx.transaction == :trans
    assert ctx.command == :cmd
  end

  test "scope to transaction resets command" do
    ctx = Context.new(:chain)
      |> Context.transaction(:trans)
      |> Context.command(:cmd)
      |> Context.transaction(:trans)

    assert ctx.chain == :chain
    assert ctx.transaction == :trans
    assert is_nil(ctx.command)
  end

  test "locks" do
    ctx = Context.new(:chain)
      |> Context.lock(%{resource: "test", resource_id: 123})
      |> Context.lock(%{resource: "test", resource_id: 456})
      |> Context.lock(%{resource: "next", resource_id: 123})

    assert Context.locked?(ctx, %{resource: "test", resource_id: 123})
    assert Context.locked?(ctx, %{resource: "test", resource_id: 456})
    assert Context.locked?(ctx, %{resource: "next", resource_id: 123})
    refute Context.locked?(ctx, %{resource: "next", resource_id: 1234})
  end

  test "context data" do
    ctx = Context.new(:chain)
      |> Context.put(:test, "Test")
      |> Context.put(123, "Yes")

    assert ctx.data.test == "Test"
    assert ctx.data[123] == "Yes"
  end
end
