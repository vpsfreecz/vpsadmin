defmodule VpsAdmin.Queue.Application do
  @moduledoc false

  use Application
  alias VpsAdmin.Queue

  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: Queue.Registry},
      Queue.QueueSupervisor,
    ]

    opts = [strategy: :rest_for_one, name: Queue.AppSupervisor]
    Supervisor.start_link(children, opts)
  end
end
