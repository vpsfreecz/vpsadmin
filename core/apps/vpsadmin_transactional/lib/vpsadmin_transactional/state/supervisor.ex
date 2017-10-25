defmodule VpsAdmin.Transactional.State.Supervisor do
  @moduledoc "Supervisor for chain state processes"

  use Supervisor

  alias VpsAdmin.Transactional
  alias VpsAdmin.Transactional.State

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @spec add_chain(chain :: Transactional.Chain.t) :: Supervisor.on_start_child
  def add_chain(chain) do
    Supervisor.start_child(__MODULE__, [chain])
  end

  def init(_arg) do
    Supervisor.init([
      Supervisor.child_spec(
        State,
        start: {State, :start_link, []}
      ),
    ], strategy: :simple_one_for_one)
  end
end
