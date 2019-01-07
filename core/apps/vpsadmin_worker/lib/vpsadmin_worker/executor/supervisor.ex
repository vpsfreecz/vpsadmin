defmodule VpsAdmin.Worker.Executor.Supervisor do
  use DynamicSupervisor

  alias VpsAdmin.Worker.Executor

  def start_link(_arg) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def run_command({t, cmd}, func) do
    {:ok, _pid} = DynamicSupervisor.start_child(
      __MODULE__,
      {Executor.Server, {{t, cmd}, func}}
    )
  end

  @impl true
  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
