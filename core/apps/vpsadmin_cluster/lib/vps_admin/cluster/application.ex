defmodule VpsAdmin.Cluster.Application do
  @moduledoc false

  use Application
  alias VpsAdmin.Cluster

  def start(_type, _args) do
    children = [
      {Cluster.Repo, []},
      {Cluster.Connector, []},
    ]

    opts = [strategy: :one_for_one, name: __MODULE__]
    Supervisor.start_link(children, opts)
  end
end
