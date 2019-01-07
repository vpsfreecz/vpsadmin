defmodule VpsAdmin.Worker.Monitor.Supervisor do
  use DynamicSupervisor

  alias VpsAdmin.Worker.Monitor

  def start_link(_arg) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def run_command({t, cmd}, func) do
    DynamicSupervisor.start_child(
      __MODULE__,
      {Monitor.Server, {{t, cmd}, func}}
    )
  end

  @impl true
  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
