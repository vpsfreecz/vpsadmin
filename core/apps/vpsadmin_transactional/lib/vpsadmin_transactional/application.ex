defmodule VpsAdmin.Transactional.Application do
  @moduledoc false

  use Application
  alias VpsAdmin.Transactional

  def start(_type, _args) do
    children = [
      Transactional.Distributor
    ]

    opts = [strategy: :one_for_one, name: Transactional.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
