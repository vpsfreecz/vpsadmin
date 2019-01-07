defmodule VpsAdmin.Worker.Distributor do
  use GenServer

  alias VpsAdmin.Worker

  ### Client interface
  def start_link(_arg) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def run_command({t, cmd}, func) do
    call_worker(cmd.node, {:run_command, {t, cmd}, func})
  end

  def report_result({t, cmd}) do
    try do
      call_supervisor({:report_result, {t, cmd}})
      :ok
    catch
      :exit, {{:nodedown, _}, _} ->
        {:error, :nodedown}

      :exit, {:noproc, _} ->
        {:error, :noproc}
    end
  end

  def retrieve_result({t, cmd}, func) do
    try do
      call_worker(cmd.node, {:retrieve_result, {t, cmd}, func})
    catch
      :exit, {{:nodedown, _}, _} ->
        {:error, :nodedown}

      :exit, {:noproc, _} ->
        {:error, :noproc}
    end
  end

  defp call_supervisor(msg) do
    GenServer.call(
      {
        __MODULE__,
        Application.get_env(:vpsadmin_transactional, :supervisor_node)
      },
      msg
    )
  end

  defp call_worker(node, msg) do
    GenServer.call({__MODULE__, node}, msg)
  end

  ### Server implementation
  @impl true
  def init(:ok) do
    {:ok, nil}
  end

  @impl true
  def handle_call({:run_command, {t, cmd}, func}, _from, state) do
    {:ok, pid} = Worker.Executor.Supervisor.run_command({t, cmd}, func)
    {:reply, {:ok, pid}, state}
  end

  def handle_call({:report_result, {t, cmd}}, _from, state) do
    Worker.Monitor.report_result({t, cmd})
    {:reply, :ok, state}
  end

  def handle_call({:retrieve_result, {t, cmd}, func}, _from, state) do
    try do
      reply = Worker.Executor.retrieve_result({t, cmd}, func)
      {:reply, reply, state}
    catch
      :exit, _ ->
        {:reply, {:error, :noproc}, state}
    end
  end
end
