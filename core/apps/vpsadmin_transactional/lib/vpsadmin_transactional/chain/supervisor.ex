defmodule VpsAdmin.Transactional.Chain.Supervisor do
  @moduledoc "Supervisor for chain execution processes"

  use Supervisor

  alias VpsAdmin.Transactional.Chain

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def add_chain(chain_id) do
    Supervisor.start_child(__MODULE__, [chain_id])
  end

  def init(_arg) do
    Supervisor.init([
      Supervisor.child_spec(
        Chain.Executor,
        start: {Chain.Executor, :start_link, []}
      ),
    ], strategy: :simple_one_for_one)
  end
end
