defmodule VpsAdmin.Transactional.RunState do
  alias VpsAdmin.Transactional.{Chain, Transaction}

  defstruct state: nil,
    queued: [],
    executing: [],
    done: [],
    failed: [],
    rollingback: [],
    rolledback: []

  @type t :: %__MODULE__{
    state: atom,
    queued: [integer],
    executing: [integer],
    done: [integer],
    failed: [integer],
    rollingback: [integer],
    rolledback: [integer],
  }

  @spec new(chain_or_transaction :: Chain.t | Transaction.t) :: t
  def new(%Chain{} = chain) do
    Map.merge(
      %__MODULE__{state: chain.state},
      sort(chain.transactions)
    )
  end

  def new(%Transaction{} = transaction) do
    Map.merge(
      %__MODULE__{state: transaction.state},
      sort(transaction.commands)
    )
  end

  defp sort(items) do
    Enum.reduce(
      items,
      %{},
      fn %{state: state} = item, acc ->
        if Map.has_key?(acc, state) do
          Map.put(acc, state, [item.id | acc.state])

        else
          Map.put(acc, state, [item.id])
        end
      end
    )
  end
end
