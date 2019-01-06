defmodule VpsAdmin.Transactional.Worker.Distributed.Monitor.Supervisor do
  use DynamicSupervisor

  alias VpsAdmin.Transactional.Worker.Distributed

  def start_link(_arg) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def run_command({t, cmd}, func) do
    DynamicSupervisor.start_child(
      __MODULE__,
      {Distributed.Monitor.Server, {{t, cmd}, func}}
    )
  end

  @impl true
  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
