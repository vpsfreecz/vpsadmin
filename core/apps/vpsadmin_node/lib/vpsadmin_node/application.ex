defmodule VpsAdmin.Node.Application do
  @moduledoc false

  use Application

  alias VpsAdmin.Node.Transaction

  def start(_type, _args) do
    children = [
      VpsAdmin.Transactional.Worker.Supervisor
    ]

    opts = [strategy: :one_for_one, name: VpsAdmin.Node.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
