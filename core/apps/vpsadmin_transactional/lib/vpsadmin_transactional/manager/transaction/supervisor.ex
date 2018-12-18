defmodule VpsAdmin.Transactional.Manager.Transaction.Supervisor do
  use DynamicSupervisor

  alias VpsAdmin.Transactional.Manager

  def start_link(_arg) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def add_transaction(trans, manager, worker) do
    IO.inspect("yo starting transaction server")

    DynamicSupervisor.start_child(
      __MODULE__,
      {Manager.Transaction.Server, {trans, manager, worker}}
    )
  end

  @impl true
  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
