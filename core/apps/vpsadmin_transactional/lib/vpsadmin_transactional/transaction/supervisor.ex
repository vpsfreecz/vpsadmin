defmodule VpsAdmin.Transactional.Transaction.Supervisor do
  @moduledoc "Supervisor for transaction execution processes"

  use Supervisor

  alias VpsAdmin.Transactional.Transaction

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def add_transaction(chain_id, transaction_id, action) do
    Supervisor.start_child(__MODULE__, [chain_id, transaction_id, action])
  end

  def init(_arg) do
    Supervisor.init([
      Supervisor.child_spec(
        Transaction.Executor,
        start: {Transaction.Executor, :start_link, []}
      ),
    ], strategy: :simple_one_for_one)
  end
end
