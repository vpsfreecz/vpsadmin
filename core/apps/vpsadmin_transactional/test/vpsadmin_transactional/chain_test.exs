defmodule VpsAdmin.Transactional.ChainTest do
  use ExUnit.Case

  alias VpsAdmin.Transactional.{Chain, Command, Transaction}

  defmodule Success do
    @behaviour Command

    def execute(params) do
      :ok
    end

    def rollback(params) do
      :ok
    end
  end

  defmodule Error do
    @behaviour Command

    def execute(params) do
      raise "error"
    end

    def rollback(params) do
      :ok
    end
  end

  defmodule Fatal do
    @behaviour Command

    def execute(params) do
      raise "fatal"
    end

    def rollback(params) do
      raise "indeed fatal"
    end
  end

  test "creating a new chain" do
    chain = Chain.new(
      10,
      :all_or_none,
      :executing,
      [
        Transaction.new(
          100,
          :all_or_none,
          :queued,
          [
            Command.new(1000, :queued, Node.self, Success, %{}),
            Command.new(1001, :queued, Node.self, Success, %{}),
            Command.new(1002, :queued, Node.self, Success, %{}),
          ]
        ),
      ]
    )

    assert chain.id == 10
    assert chain.strategy == :all_or_none
    assert chain.state == :executing
    assert chain.nodes == [Node.self]
    assert length(chain.transactions) == 1

    t = List.first(chain.transactions)
    assert t.id == 100
    assert t.strategy == :all_or_none
    assert t.state == :queued
    assert length(t.commands) == 3
  end

  test "executing a chain" do
    chain = Chain.new(
      10,
      :all_or_none,
      :executing,
      [
        Transaction.new(
          100,
          :all_or_none,
          :queued,
          [
            Command.new(1000, :queued, Node.self, Success, %{}),
            Command.new(1001, :queued, Node.self, Success, %{}),
            Command.new(1002, :queued, Node.self, Success, %{}),
          ]
        ),
      ]
    )

    assert chain.nodes == [Node.self]

    Chain.run(chain)
  end
end
