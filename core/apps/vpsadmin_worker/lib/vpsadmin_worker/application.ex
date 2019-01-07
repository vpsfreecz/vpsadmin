defmodule VpsAdmin.Worker.Application do
  @moduledoc false

  use Application
  alias VpsAdmin.Worker
  alias VpsAdmin.Worker.{Distributor, Executor, Monitor, NodeCtldCommand}

  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: Worker.Registry},
      Distributor,
      Monitor.Supervisor,
      Executor.Supervisor,
      NodeCtldCommand.Supervisor
    ]

    opts = [strategy: :rest_for_one, name: Worker.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
