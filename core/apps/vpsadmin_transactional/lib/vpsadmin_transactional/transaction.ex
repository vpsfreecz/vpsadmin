defmodule VpsAdmin.Transactional.Transaction do
  alias VpsAdmin.Transactional.{Command, Transaction}

  @enforce_keys [:id, :commands, :state, :strategy]

  defstruct [:id, :commands, :state, :strategy]

  @type t :: %__MODULE__{
    id: integer,
    commands: [Command.t, ...],
    state: atom,
    strategy: atom,
  }

  def new(id, strategy, state, commands) do
    %__MODULE__{
      id: id,
      state: state,
      commands: commands,
      strategy: strategy,
    }
  end

  @spec nodes(transaction :: t) :: [Node.t, ...]
  def nodes(transaction) do
    transaction.commands
    |> Enum.map(&(&1.node))
    |> Enum.uniq()
  end

  def execute(chain_id, t_id) do
    Transaction.Supervisor.add_transaction(chain_id, t_id, :execute)
  end

  def rollback(chain_id, t_id) do
    Transaction.Supervisor.add_transaction(chain_id, t_id, :rollback)
  end
end
