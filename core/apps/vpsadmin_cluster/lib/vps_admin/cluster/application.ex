defmodule VpsAdmin.Cluster.Application do
  @moduledoc false

  use Application
  alias VpsAdmin.Cluster

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    children = [
      supervisor(Cluster.Repo, []),
      worker(Cluster.Transaction.Processes, []),
      worker(Cluster.Connector, [], restart: :transient),
    ]

    opts = [strategy: :one_for_one, name: __MODULE__]
    Supervisor.start_link(children, opts)
  end
end
