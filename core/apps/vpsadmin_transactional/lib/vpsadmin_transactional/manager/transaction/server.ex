defmodule VpsAdmin.Transactional.Manager.Transaction.Server do
  use GenServer, restart: :transient

  require Logger
  alias VpsAdmin.Transactional.Manager
  alias VpsAdmin.Transactional.Worker
  alias VpsAdmin.Transactional.Distributor

  ### Client interface
  def start_link({{trans, cmds}, manager, worker}) do
    GenServer.start_link(
      __MODULE__,
      {{trans, cmds}, manager, worker},
      name: via_tuple(trans)
    )
  end

  def report_result({t, cmd}) do
    GenServer.cast(via_tuple(t), {:report_result, cmd})
  end

  def via_tuple(id) when is_integer(id) do
    {:via, Registry, {Manager.Transaction.Registry, {:transaction, id}}}
  end

  def via_tuple(trans) when is_map(trans) do
    via_tuple(trans.id)
  end

  ### Server implementation
  @impl true
  def init({{trans, cmds}, manager, worker}) do
    Logger.debug("Starting manager for transaction #{trans.id} (#{manager}, #{worker})")

    {
      :ok,
      %{
        transaction: trans,
        commands: cmds,
        manager: manager,
        worker: worker
      },
      {:continue, :startup}
    }
  end

  @impl true
  def handle_continue(:startup, %{transaction: trans, commands: cmds} = state) do
    queue = make_queue(trans.state, cmds)

    case process_queue(state, queue) do
      v when v in ~w(done failed)a ->
        close(trans, v, state.manager)
        {:stop, :normal, state}

      new_queue ->
        {
          :noreply,
          state
          |> Map.delete(:commands)
          |> Map.put(:queue, new_queue)
          |> Map.put(:done, [])
        }
    end
  end

  @impl true
  def handle_cast({:report_result, %{state: :executed, status: :done} = cmd}, state) do
    Logger.debug("Command #{state.transaction.id}:#{cmd.id} executed")
    state.manager.command_finished(state.transaction, cmd)

    [_ | queue] = state.queue

    case process_queue(state, queue) do
      :done ->
        close(state.transaction, :done, state.manager)
        {:stop, :normal, state}

      new_queue when is_list(new_queue) ->
        {:noreply, %{state | queue: new_queue, done: [cmd | state.done]}}
    end
  end

  def handle_cast({:report_result, %{state: :executed, status: :failed} = cmd}, state) do
    Logger.debug("Command #{state.transaction.id}:#{cmd.id} failed to execute")
    state.manager.command_finished(state.transaction, cmd)

    case handle_failure(state.transaction.state, cmd.reversible) do
      :continue ->
        Logger.debug("Continuing execution of transaction #{state.transaction.id}")
        [_ | queue] = state.queue

        case process_queue(state, queue) do
          v when v in ~w(done failed)a ->
            close(state.transaction, v, state.manager)
            {:stop, :normal, state}

          new_queue when is_list(new_queue) ->
            {:noreply, %{state | queue: new_queue, done: [cmd | state.done]}}
        end

      :rollback ->
        Logger.debug("Initiating rollback of transaction #{state.transaction.id}")
        new_state = rollback(state, cmd)

        case process_queue(new_state, new_state.queue) do
          new_queue when is_list(new_queue) ->
            {:noreply, %{new_state | queue: new_queue, done: [cmd | state.done]}}
        end

        {:noreply, new_state}

      :close ->
        Logger.debug("Prematurely closing transaction #{state.transaction.id}")
        close(state.transaction, :failed, state.manager)
        {:noreply, state}

      :abort ->
        Logger.debug("Aborting transaction #{state.transaction.id}")
        abort(state.transaction, state.manager)
        {:stop, :normal, state}
    end
  end

  def handle_cast({:report_result, %{state: :rolledback, status: :done} = cmd}, state) do
    Logger.debug("Command #{state.transaction.id}:#{cmd.id} rolled back")
    state.manager.command_finished(state.transaction, cmd)

    [_ | queue] = state.queue

    case process_queue(state, queue) do
      :failed ->
        close(state.transaction, :failed, state.manager)
        {:stop, :normal, state}

      new_queue when is_list(new_queue) ->
        {:noreply, %{state | queue: new_queue, done: [cmd | state.done]}}
    end
  end

  def handle_cast({:report_result, %{state: :rolledback, status: :failed} = cmd}, state) do
    Logger.debug("Command #{state.transaction.id}:#{cmd.id} failed to rollback")
    state.manager.command_finished(state.transaction, cmd)

    case handle_failure(state.transaction.state, cmd.reversible) do
      :continue ->
        Logger.debug("Continuing rollback of transaction #{state.transaction.id}")
        [_ | queue] = state.queue

        case process_queue(state, queue) do
          :failed ->
            close(state.transaction, :failed, state.manager)
            {:stop, :normal, state}

          new_queue when is_list(new_queue) ->
            {:noreply, %{state | queue: new_queue, done: [cmd | state.done]}}
        end

      :close ->
        Logger.debug("Prematurely closing transaction #{state.transaction.id}")
        close(state.transaction, :failed, state.manager)
        {:noreply, state}

      :abort ->
        Logger.debug("Aborting transaction #{state.transaction.id}")
        abort(state.transaction, state.manager)
        {:stop, :normal, state}
    end
  end

  defp make_queue(:executing, commands) do
    commands
    |> Enum.drop_while(&(&1.state == :executed))
  end

  defp make_queue(:rollingback, commands) do
    commands
    |> Enum.reverse()
    |> Enum.drop_while(&(&1.state == :rolledback || &1.state == :queued))
  end

  defp process_queue(%{transaction: %{state: :executing}}, []) do
    :done
  end

  defp process_queue(%{transaction: %{state: :rollingback}}, []) do
    :failed
  end

  defp process_queue(%{transaction: %{state: :executing}} = state, [h | t]) do
    {:queued, nil} = {h.state, h.status}
    run(state.manager, state.worker, {state.transaction, h}, :execute)
    [h | t]
  end

  defp process_queue(%{transaction: %{state: :rollingback}} = state, [h | t]) do
    {:executed, _} = {h.state, h.status}
    run(state.manager, state.worker, {state.transaction, h}, :rollback)
    [h | t]
  end

  defp rollback(state, cmd) do
    %{
      state
      | queue: [cmd | state.done],
        done: [],
        transaction: %{state.transaction | state: :rollingback}
    }
  end

  defp run(manager, worker, {t, cmd}, :execute = func) do
    new_cmd = %{cmd | state: :executed}
    manager.command_started(t, new_cmd)
    worker.run_command({t.id, new_cmd}, func)
  end

  defp run(manager, worker, {t, cmd}, :rollback = func) do
    new_cmd = %{cmd | state: :rolledback}
    manager.command_started(t, new_cmd)
    worker.run_command({t.id, new_cmd}, func)
  end

  defp handle_failure(:executing, :ignore), do: :continue
  defp handle_failure(:executing, :reversible), do: :rollback
  defp handle_failure(:executing, :irreversible), do: :close
  defp handle_failure(:rollingback, :ignore), do: :continue
  defp handle_failure(:rollingback, _reversible), do: :abort

  defp close(trans, state, manager) do
    manager.close_transaction(%{trans | state: state})
  end

  defp abort(trans, manager) do
    manager.abort_transaction(%{trans | state: :aborted})
  end
end
