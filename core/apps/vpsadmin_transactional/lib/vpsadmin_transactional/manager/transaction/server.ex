defmodule VpsAdmin.Transactional.Manager.Transaction.Server do
  use GenServer, restart: :transient

  require Logger
  alias VpsAdmin.Transactional.Manager
  alias VpsAdmin.Transactional.Transaction

  ### Client interface
  def start_link({trans_id, manager, worker}) do
    GenServer.start_link(
      __MODULE__,
      {trans_id, manager, worker},
      name: via_tuple(trans_id)
    )
  end

  def abort(trans_id) do
    GenServer.call(via_tuple(trans_id), :abort)
  end

  def report_result({t, cmd}) do
    GenServer.cast(via_tuple(t), {:report_result, cmd})
  end

  defp via_tuple(id) when is_integer(id) do
    {:via, Registry, {Manager.Transaction.Registry, {:transaction, id}}}
  end

  defp via_tuple(%Transaction{} = trans) do
    via_tuple(trans.id)
  end

  ### Server implementation
  @impl true
  def init({trans_id, manager, worker}) do
    Logger.debug("Starting manager for transaction #{trans_id} (#{manager}, #{worker})")

    {
      :ok,
      %{
        id: trans_id,
        manager: manager,
        worker: worker
      },
      {:continue, :startup}
    }
  end

  @impl true
  def handle_continue(:startup, %{id: id} = state) do
    with %Transaction{} = trans <- state.manager.get_transaction(id),
         cmds when is_list(cmds) <- state.manager.get_commands(id),
         queue <- make_queue(trans.state, cmds) do
      new_state =
        state
        |> Map.delete(:id)
        |> Map.put(:transaction, trans)
        |> Map.put(:done, [])

      case process_queue(new_state, queue) do
        v when v in ~w(done failed)a ->
          close(trans, v, new_state.manager)
          {:stop, :normal, new_state}

        {:ok, new_queue, ref} ->
          {
            :noreply,
            new_state
            |> Map.put(:queue, new_queue)
            |> Map.put(:ref, ref)
          }

        {:error, _error, cmd, new_queue} ->
          handle_result(cmd, Map.put(new_state, :queue, new_queue))

        {:unavailable, time, new_queue} ->
          reschedule(Map.put(new_state, :queue, new_queue), time)
      end
    else
      {:error, error} ->
        {:stop, error, state}
    end
  end

  @impl true
  def handle_call(:abort, _from, %{timer: _} = state) do
    do_abort(state.transaction, state.manager)
    {:stop, :normal, :ok, state}
  end

  def handle_call(:abort, _from, state) do
    {:reply, :ok, Map.put(state, :abort, true)}
  end

  @impl true
  def handle_cast({:report_result, cmd}, state) do
    Process.demonitor(state.ref)
    handle_result(cmd, state)
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _object, reason}, %{ref: ref} = state) do
    Logger.debug("Executed command exited prematurely")
    IO.inspect(reason)
    [cmd | _] = state.queue
    handle_result(%{cmd | status: :failed}, state)
  end

  def handle_info({:DOWN, _ref, :process, _object, _reason}, state) do
    Logger.debug("Ignoring irrelevant monitor notification")
    {:noreply, state}
  end

  def handle_info(:retry, state) do
    new_state = Map.delete(state, :timer)

    case process_queue(new_state, new_state.queue) do
      v when v in ~w(done failed)a ->
        close(state.transaction, v, new_state.manager)
        {:stop, :normal, new_state}

      {:ok, new_queue, ref} ->
        {
          :noreply,
          new_state
          |> Map.put(:queue, new_queue)
          |> Map.put(:ref, ref)
        }

      {:error, _error, cmd, new_queue} ->
        handle_result(cmd, Map.put(new_state, :queue, new_queue))

      {:unavailable, time, new_queue} ->
        reschedule(Map.put(new_state, :queue, new_queue), time)
    end
  end

  defp handle_result(cmd, %{abort: true} = state) do
    Logger.debug("Command #{state.transaction.id}:#{cmd.id} finished")
    state.manager.command_finished(state.transaction, cmd)

    Logger.debug("Aborting transaction #{state.transaction.id}")
    do_abort(state.transaction, state.manager)
    {:stop, :normal, state}
  end

  defp handle_result(%{state: :executed, status: :done} = cmd, state) do
    Logger.debug("Command #{state.transaction.id}:#{cmd.id} executed")
    state.manager.command_finished(state.transaction, cmd)

    [_ | queue] = state.queue

    case process_queue(state, queue) do
      :done ->
        close(state.transaction, :done, state.manager)
        {:stop, :normal, state}

      {:ok, new_queue, ref} ->
        {
          :noreply,
          state
          |> Map.put(:queue, new_queue)
          |> Map.put(:done, [cmd | state.done])
          |> Map.put(:ref, ref)
        }

      {:error, _error, cmd, new_queue} ->
        handle_result(cmd, %{state | queue: new_queue})

      {:unavailable, time, new_queue} ->
        reschedule(Map.put(state, :queue, new_queue), time)
    end
  end

  defp handle_result(%{state: :executed, status: :failed} = cmd, state) do
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

          {:ok, new_queue, ref} ->
            {
              :noreply,
              state
              |> Map.put(:queue, new_queue)
              |> Map.put(:done, [cmd | state.done])
              |> Map.put(:ref, ref)
            }

          {:error, _error, cmd, new_queue} ->
            handle_result(cmd, %{state | queue: new_queue})

          {:unavailable, time, new_queue} ->
            reschedule(Map.put(state, :queue, new_queue), time)
        end

      :rollback ->
        Logger.debug("Initiating rollback of transaction #{state.transaction.id}")
        new_state = rollback(state, cmd)

        case process_queue(new_state, new_state.queue) do
          {:ok, new_queue, ref} ->
            {
              :noreply,
              new_state
              |> Map.put(:queue, new_queue)
              |> Map.put(:done, [cmd | state.done])
              |> Map.put(:ref, ref)
            }

          {:error, _error, cmd, new_queue} ->
            handle_result(cmd, %{new_state | queue: new_queue})

          {:unavailable, time, new_queue} ->
            reschedule(Map.put(new_state, :queue, new_queue), time)
        end

      :close ->
        Logger.debug("Prematurely closing transaction #{state.transaction.id}")
        close(state.transaction, :failed, state.manager)
        {:noreply, state}

      :abort ->
        Logger.debug("Aborting transaction #{state.transaction.id}")
        do_abort(state.transaction, state.manager)
        {:stop, :normal, state}
    end
  end

  defp handle_result(%{state: :rolledback, status: :done} = cmd, state) do
    Logger.debug("Command #{state.transaction.id}:#{cmd.id} rolled back")
    state.manager.command_finished(state.transaction, cmd)

    [_ | queue] = state.queue

    case process_queue(state, queue) do
      :failed ->
        close(state.transaction, :failed, state.manager)
        {:stop, :normal, state}

      {:ok, new_queue, ref} ->
        {
          :noreply,
          state
          |> Map.put(:queue, new_queue)
          |> Map.put(:done, [cmd | state.done])
          |> Map.put(:ref, ref)
        }

      {:error, _error, cmd, new_queue} ->
        handle_result(cmd, %{state | queue: new_queue})

      {:unavailable, time, new_queue} ->
        reschedule(Map.put(state, :queue, new_queue), time)
    end
  end

  defp handle_result(%{state: :rolledback, status: :failed} = cmd, state) do
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

          {:ok, new_queue, ref} ->
            {
              :noreply,
              state
              |> Map.put(:queue, new_queue)
              |> Map.put(:done, [cmd | state.done])
              |> Map.put(:ref, ref)
            }

          {:error, _error, cmd, new_queue} ->
            handle_result(cmd, %{state | queue: new_queue, done: [cmd | state.done]})

          {:unavailable, time, new_queue} ->
            reschedule(Map.put(state, :queue, new_queue), time)
        end

      :close ->
        Logger.debug("Prematurely closing transaction #{state.transaction.id}")
        close(state.transaction, :failed, state.manager)
        {:noreply, state}

      :abort ->
        Logger.debug("Aborting transaction #{state.transaction.id}")
        do_abort(state.transaction, state.manager)
        {:stop, :normal, state}
    end
  end

  defp reschedule(state, time) do
    Logger.debug("Executor unavailable, will retry in #{time} ms")
    {:noreply, Map.put(state, :timer, Process.send_after(self(), :retry, time))}
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

  defp process_queue(%{abort: true}, _) do
    :abort
  end

  defp process_queue(%{transaction: %{state: :executing}}, []) do
    :done
  end

  defp process_queue(%{transaction: %{state: :rollingback}}, []) do
    :failed
  end

  defp process_queue(%{transaction: %{state: :executing}} = state, [h | t]) do
    {:queued, nil} = {h.state, h.status}

    case run(state.manager, state.worker, {state.transaction, h}, :execute) do
      {:ok, cmd, ref} ->
        {:ok, [cmd | t], ref}

      {:error, error, cmd} ->
        {:error, error, %{cmd | status: :failed}, [h | t]}

      {:unavailable, time, _cmd} ->
        {:unavailable, time, [h | t]}
    end
  end

  defp process_queue(%{transaction: %{state: :rollingback}} = state, [h | t]) do
    {:executed, _} = {h.state, h.status}

    case run(state.manager, state.worker, {state.transaction, h}, :rollback) do
      {:ok, cmd, ref} ->
        {:ok, [cmd | t], ref}

      {:error, error, cmd} ->
        {:error, error, %{cmd | status: :failed}, [h | t]}

      {:unavailable, time, _cmd} ->
        {:unavailable, time, [h | t]}
    end
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
    do_run(manager, worker, {t, %{cmd | state: :executed}}, func)
  end

  defp run(manager, worker, {t, cmd}, :rollback = func) do
    do_run(manager, worker, {t, %{cmd | state: :rolledback}}, func)
  end

  defp do_run(manager, worker, {t, cmd}, func) do
    manager.command_started(t, cmd)

    case worker.run_command({t.id, cmd}, func) do
      {:ok, pid} ->
        {:ok, cmd, Process.monitor(pid)}

      {:error, error} ->
        {:error, error, cmd}

      {:unavailable, time} ->
        {:unavailable, time, cmd}
    end
  end

  defp handle_failure(:executing, :ignore), do: :continue
  defp handle_failure(:executing, :reversible), do: :rollback
  defp handle_failure(:executing, :irreversible), do: :close
  defp handle_failure(:rollingback, :ignore), do: :continue
  defp handle_failure(:rollingback, _reversible), do: :abort

  defp close(trans, state, manager) do
    manager.close_transaction(%{trans | state: state})
  end

  defp do_abort(trans, manager) do
    manager.abort_transaction(%{trans | state: :aborted})
  end
end
