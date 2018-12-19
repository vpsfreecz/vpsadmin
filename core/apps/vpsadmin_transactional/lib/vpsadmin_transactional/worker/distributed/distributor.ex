defmodule VpsAdmin.Transactional.Worker.Distributed.Distributor do
  use GenServer

  alias VpsAdmin.Transactional.Manager
  alias VpsAdmin.Transactional.Worker.Distributed

  ### Client interface
  def start_link(_arg) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def run_command({t, cmd}, func) do
    GenServer.call({__MODULE__, cmd.node}, {:run_command, {t, cmd}, func})
  end

  def report_result({t, cmd}) do
    # TODO: send to node with supervisor running
    Manager.Transaction.Server.report_result({t, cmd})
  end

  ### Server implementation
  @impl true
  def init(:ok) do
    {:ok, nil}
  end

  @impl true
  def handle_call({:run_command, {t, cmd}, func}, _from, state) do
    Distributed.Executor.run_command({t, cmd}, func)
    {:reply, :ok, state}
  end
end
