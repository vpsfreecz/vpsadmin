defmodule VpsAdmin.Persistence.Application do
  @moduledoc false

  use Application
  alias VpsAdmin.Persistence

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    children = [
      supervisor(Persistence.Repo, []),
      worker(Persistence.Transaction.Processes, []),
    ]

    opts = [strategy: :one_for_one, name: VpsAdmin.Persistence.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
