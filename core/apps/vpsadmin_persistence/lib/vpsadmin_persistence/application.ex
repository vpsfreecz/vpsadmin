defmodule VpsAdmin.Persistence.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      VpsAdmin.Persistence.Repo
    ]

    opts = [strategy: :one_for_one, name: VpsAdmin.Persistence.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
