defmodule VpsAdmin.Transactional.Worker.Supervisor do
  use Supervisor

  alias VpsAdmin.Transactional
  alias VpsAdmin.Transactional.Worker

  def start_link(opts \\ [queues: []]) do
    Supervisor.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    children = [
      Transactional.Queue.MainSupervisor,
      Worker.Command.Supervisor,
      Worker.Executor
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
