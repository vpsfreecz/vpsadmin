defmodule VpsAdmin.Transactional.Worker.Distributed.ResultReporter.Supervisor do
  use DynamicSupervisor

  alias VpsAdmin.Transactional.Worker.Distributed

  def start_link(_arg) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def report({t, cmd}) do
    DynamicSupervisor.start_child(
      __MODULE__,
      {Distributed.ResultReporter.Server, {t, cmd}}
    )
  end

  @impl true
  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
