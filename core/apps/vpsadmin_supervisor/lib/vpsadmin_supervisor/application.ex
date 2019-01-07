defmodule VpsAdmin.Supervisor.Application do
  @moduledoc false

  use Application
  alias VpsAdmin.Supervisor.Manager, as: MyManager
  alias VpsAdmin.Supervisor.Connector
  alias VpsAdmin.Supervisor.ChainPoller
  alias VpsAdmin.Transactional.Manager

  def start(_type, _args) do
    children = [
      {Manager.Supervisor, {MyManager, VpsAdmin.Worker}},
      Connector,
      ChainPoller
    ]

    opts = [strategy: :rest_for_one, name: VpsAdmin.Supervisor.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
