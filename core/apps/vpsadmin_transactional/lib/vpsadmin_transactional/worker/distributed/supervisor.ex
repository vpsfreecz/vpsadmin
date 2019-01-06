defmodule VpsAdmin.Transactional.Worker.Distributed.Supervisor do
  use Supervisor

  alias VpsAdmin.Transactional.Worker.Distributed

  def start_link(_opts) do
    Supervisor.start_link(__MODULE__, :ok)
  end

  @impl true
  def init(:ok) do
    children = [
      {Registry, keys: :unique, name: Distributed.Registry},
      Distributed.Executor.Supervisor,
      Distributed.NodeCtldCommand.Supervisor
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
