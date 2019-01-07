defmodule VpsAdmin.Transactional.Worker.Distributed.Monitor.Server do
  use GenServer, restart: :temporary

  require Logger
  alias VpsAdmin.Transactional.Manager
  alias VpsAdmin.Transactional.Worker.Distributed.Distributor

  ### Client interface
  def start_link({{t, cmd}, _func} = arg) do
    GenServer.start_link(__MODULE__, arg, name: via_tuple({t, cmd}))
  end

  def report_result({t, cmd}) do
    GenServer.cast(via_tuple({t, cmd}), {:report_result, cmd})
  end

  defp via_tuple({t, cmd}) do
    # TODO: registry?
    {:via, Registry, {Manager.Transaction.Registry, {:monitor, t, cmd.id}}}
  end

  ### Server implementation
  @impl true
  def init({{t, cmd}, func}) do
    {:ok, %{
      command: {t, cmd},
      func: func,
      ref: nil,
      node: nil,
      timer: nil
    }, {:continue, :startup}}
  end

  @impl true
  def handle_continue(:startup, %{command: {t, cmd}, func: func} = state) do
    case check_executor({t, cmd}, func) do
      {:ok, :notfound} ->
        do_start(state)

      {:ok, {:running, pid}} ->
        {:noreply, %{state | ref: Process.monitor(pid)}}

      {:ok, {:done, result}} ->
        Manager.report_result({t, result})
        {:stop, :normal, state}

      {:error, :badfunc} ->
        {:stop, :badfunc, state}
    end
  end

  @impl true
  def handle_cast({:report_result, result}, %{command: {t, _}} = state) do
    Manager.report_result({t, result})
    {:stop, :normal, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _object, :noconnection}, %{ref: ref} = state) do
    Logger.debug("Lost connection to executor process")
    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, _object, reason}, %{ref: ref} = state) do
    Logger.debug("Executor process exited with #{inspect(reason)}")
    {:stop, reason, state}
  end

  def handle_info({:DOWN, _ref, :process, _object, _reason}, state) do
    Logger.debug("Ignoring invalid monitor message")
    {:noreply, state}
  end

  def handle_info({:nodeup, node}, %{node: node, command: {t, cmd}, func: func} = state) do
    Logger.debug("Node #{node} with command executor has come back online")

    new_state =
      if state.timer do
        Process.cancel_timer(state.timer)
        %{state | timer: nil}
      else
        state
      end

    case recover_executor({t, cmd}, func) do
      {:ok, {:running, pid}} ->
        {:noreply, %{new_state | ref: Process.monitor(pid)}}

      {:ok, {:done, result}} ->
        Manager.report_result({t, result})
        {:stop, :normal, new_state}

      {:error, :badfunc, nil} ->
        {:stop, :badfunc, new_state}

      {:error, _error, timer} ->
        {:noreply, %{state | timer: timer}}
    end
  end

  def handle_info({:nodeup, _node}, state), do: {:noreply, state}

  def handle_info({:nodedown, node}, %{node: node, timer: t} = state) when not is_nil(t) do
    Process.cancel_timer(t)
    {:noreply, %{state | timer: nil}}
  end

  def handle_info({:nodedown, _node}, state), do: {:noreply, state}

  def handle_info({:retry, :start}, %{ref: nil} = state) do
    do_start(state)
  end

  defp check_executor({t, cmd}, func) do
    case Distributor.retrieve_result({t, cmd}, func) do
      {:ok, _} = v ->
        v

      {:error, :badfunc} = v ->
        v

      {:error, _} ->
        {:ok, :notfound}
    end
  end

  defp do_start(%{command: {t, cmd}, func: func} = state) do
    new_state =
      case start_executor({t, cmd}, func) do
        {:ok, node, ref} ->
          %{state | ref: ref, node: node}

        {:error, _error, timer} ->
          %{state | timer: timer}
      end

    {:noreply, new_state}
  end

  defp start_executor({t, cmd}, func) do
    try do
      {:ok, pid} = Distributor.run_command({t, cmd}, func)
      Logger.debug("Remote command executor has been started")

      :net_kernel.monitor_nodes(true)
      {:ok, node(pid), Process.monitor(pid)}

    catch
      :exit, {{:nodedown, _}, _} ->
        Logger.debug("Unable to start remote command executor (nodedown)")
        {:error, :nodedown, reschedule_start()}

      :exit, {:noproc, _} ->
        Logger.debug("Unable to start remote command executor (noproc)")
        {:error, :noproc, reschedule_start()}
    end
  end

  defp reschedule_start do
    Process.send_after(self(), {:retry, :start}, 10_000)
  end

  defp recover_executor({t, cmd}, func) do
    case Distributor.retrieve_result({t, cmd}, func) do
      {:ok, _} = v ->
        v

      {:error, :nodedown} ->
        {:error, :nodedown, nil}

      {:error, :noproc} ->
        {:error, :noproc, reschedule_recovery()}

      {:error, :badfunc} ->
        {:error, :badfunc, nil}
    end
  end

  defp reschedule_recovery do
    Process.send_after(self(), {:retry, :recovery}, 10_000)
  end
end
