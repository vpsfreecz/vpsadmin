defmodule VpsAdmin.Transactional.Worker.Distributed.Supervisor do
  use Supervisor

  alias VpsAdmin.Transactional
  alias VpsAdmin.Transactional.Worker.Distributed

  def start_link(opts \\ [queues: []]) do
    Supervisor.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    children = [
      Distributed.Command.Supervisor,
      Distributed.Executor
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
