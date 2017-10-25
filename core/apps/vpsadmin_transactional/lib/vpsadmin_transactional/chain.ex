defmodule VpsAdmin.Transactional.Chain do
  alias VpsAdmin.Transactional
  alias VpsAdmin.Transactional.{Chain, Transaction}

  @enforce_keys [:id, :nodes, :transactions, :state, :strategy]

  defstruct [:id, :nodes, :transactions, :state, :strategy]

  @type t :: %__MODULE__{
    id: integer,
    nodes: [Node.t, ...],
    transactions: [Transaction.t, ...],
    state: atom,
    strategy: atom,
  }

  def new(id, strategy, state, transactions) do
    %__MODULE__{
      id: id,
      state: state,
      transactions: transactions,
      nodes: transactions |> Enum.map(&Transaction.nodes/1) |> List.flatten() |> Enum.uniq(),
      strategy: strategy,
    }
  end

  def run(chain) do
    Chain.Controller.new(chain)
  end
end
