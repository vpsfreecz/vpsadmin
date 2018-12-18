defmodule VpsAdmin.Transactional.Worker.Command.Supervisor do
  use DynamicSupervisor

  alias VpsAdmin.Transactional.Worker

  def start_link(_arg) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def run_command(cmd, func) do
    IO.inspect("yo starting command server")

    DynamicSupervisor.start_child(
      __MODULE__,
      {Worker.Command.Server, {cmd, func}}
    )
  end

  @impl true
  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
