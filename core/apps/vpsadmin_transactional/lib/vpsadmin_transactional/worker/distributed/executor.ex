defmodule VpsAdmin.Transactional.Worker.Distributed.Executor do
  use GenServer

  require Logger
  alias VpsAdmin.Transactional.Worker.Distributed
  alias VpsAdmin.Queue

  ### Client interface
  def start_link(_arg) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def run_command({t, cmd}, func) do
    GenServer.call(__MODULE__, {:run_command, {t, cmd}, func})
  end

  ### Server implementation
  @impl true
  def init(:ok) do
    {:ok, %{commands: []}}
  end

  @impl true
  def handle_call({:run_command, {t, cmd}, func}, _from, state) do
    :ok =
      Queue.enqueue(
        cmd.queue,
        {t, cmd},
        {Distributed.Command.Server, :run, [{t, cmd}, func]},
        self()
      )

    {:reply, :ok, state}
  end

  @impl true
  def handle_cast({:queue, {t, cmd}, :executing}, state) do
    Logger.debug("Begun execution/rollback of command #{t}:#{cmd.id}")
    {:noreply, state}
  end

  def handle_cast({:queue, {t, cmd}, :done, :normal}, state) do
    Logger.debug("Eecution/rollback of command #{t}:#{cmd.id}")
    {:noreply, state}
  end

  def handle_cast({:queue, {t, cmd}, :done, reason}, state) do
    Logger.debug(
      "Eecution/rollback of command #{t}:#{cmd.id} failed with "<>
      "'#{inspect(reason)}'"
    )
    Distributed.Distributor.report_result(
      {state.t, %{state.cmd | status: :failed, output: %{error: reason}}}
    )
    {:noreply, state}
  end
end
