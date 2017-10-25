defmodule VpsAdmin.Transactional.Application do
  @moduledoc false

  use Application

  alias VpsAdmin.Transactional.{Chain, Queue, State, Transaction}

  def start(_type, _args) do
    children = [
      {Registry, [keys: :unique, name: VpsAdmin.Transactional.Registry]},
      {Queue.Supervisor, []},
      {State.Supervisor, []},
      {Chain.Supervisor, []},
      {Transaction.Supervisor, []},
      {Chain.Controller, []},
    ]

    opts = [strategy: :one_for_one, name: VpsAdmin.Transactional.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
