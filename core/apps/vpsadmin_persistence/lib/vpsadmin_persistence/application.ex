defmodule VpsAdmin.Persistence.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  alias VpsAdmin.Persistence

  def start(_type, _args) do
    children = [
      Persistence.Repo,
      Persistence.ReliableQuery.Supervisor
    ]

    opts = [strategy: :one_for_one, name: Persistence.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
