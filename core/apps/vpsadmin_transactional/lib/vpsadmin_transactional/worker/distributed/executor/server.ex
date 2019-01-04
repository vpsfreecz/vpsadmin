defmodule VpsAdmin.Transactional.Worker.Distributed.Executor.Server do
  use GenServer, restart: :transient

  require Logger
  alias VpsAdmin.Transactional.Command
  alias VpsAdmin.Transactional.Worker.Distributed
  alias VpsAdmin.Queue

  ### Client interface
  def start_link({t, cmd, func} = arg) do
    GenServer.start_link(__MODULE__, arg)
  end

  def report_result({t, cmd}) do
    GenServer.cast(via_tuple({t, cmd}), {:result, {t, cmd}})
  end

  defp via_tuple({t, cmd}) do
    {:via, Registry, {Distributed.Registry, {:executor, t, cmd.id}}}
  end

  ### Server implementation
  @impl true
  def init({t, cmd, func} = arg) do
    {:ok, arg, {:continue, :startup}}
  end

  @impl true
  def handle_continue(:startup, {t, cmd, func}) do
    case run_command({t, cmd}, func) do
      {:ok, {t, cmd}} ->
        {:noreply, {t, cmd}}

      {:stop, {t, cmd}} ->
        {:stop, :normal, {t, cmd}}
    end
  end

  @impl true
  def handle_cast({:result, {t, cmd}}, _state) do
    Logger.debug("Reporting result of command #{t}:#{cmd.id}")
    Distributed.Distributor.report_result({t, cmd})
    {:noreply, {t, cmd}}
  end

  def handle_cast({:queue, {t, cmd}, :executing}, {t, cmd} = state) do
    Logger.debug("Begun execution/rollback of command #{t}:#{cmd.id}")
    {:noreply, state}
  end

  def handle_cast({:queue, {t, cmd}, :done, :normal}, {t, cmd} = state) do
    Logger.debug("Execution/rollback of command #{t}:#{cmd.id} finished")
    {:stop, :normal, state}
  end

  def handle_cast({:queue, {t, cmd}, :done, reason}, {t, cmd} = state) do
    Logger.debug(
      "Execution/rollback of command #{t}:#{cmd.id} failed with "<>
      "'#{inspect(reason)}'"
    )
    Distributed.Distributor.report_result(
      {state.t, %{state.cmd | status: :failed, output: %{error: reason}}}
    )
    {:stop, :normal, state}
  end

  def handle_cast({:queue, {:transaction, t}, :reserved}, {t, cmd} = state) do
    Logger.debug("Reserved slot(s) in queue #{cmd.queue}")
    Distributed.Distributor.report_result({t, %{cmd | status: :done}})
    {:stop, :normal, state}
  end

  # Queue slot reservation
  defp run_command({t, %Command{input: %{handle: 101}} = cmd}, :execute) do
    :ok = Queue.reserve(
      cmd.queue,
      {:transaction, t},
      1,
      self(),
      priority: cmd.input.priority
    )
    {:ok, {t, cmd}}
  end

  defp run_command({t, %Command{input: %{handle: 101}} = cmd}, :rollback) do
    Queue.release(cmd.queue, {:transaction, t}, 1)
    new_cmd = %{cmd | status: :done}
    Distributed.Distributor.report_result({t, new_cmd})
    {:stop, {t, cmd}}
  end

  # Queue slot release
  defp run_command({t, %Command{input: %{handle: 102}} = cmd}, :execute) do
    Queue.release(cmd.queue, {:transaction, t}, 1)
    new_cmd = %{cmd | status: :done}
    Distributed.Distributor.report_result({t, new_cmd})
    {:stop, {t, new_cmd}}
  end

  defp run_command({t, %Command{input: %{handle: 102}} = cmd}, :rollback) do
    new_cmd = %{cmd | status: :done}
    Distributed.Distributor.report_result({t, new_cmd})
    {:stop, {t, new_cmd}}
  end

  # nodectld commands
  defp run_command({t, cmd}, func) do
    :ok =
      Queue.enqueue(
        cmd.queue,
        {t, cmd},
        {Distributed.NodeCtldCommand.Supervisor, :run_command, [{t, cmd}, func]},
        self(),
        name: {:transaction, t},
        priority: cmd.input.priority
      )

    {:ok, {t, cmd}}
  end
end
