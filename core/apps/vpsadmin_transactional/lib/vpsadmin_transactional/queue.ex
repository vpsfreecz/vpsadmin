defmodule VpsAdmin.Transactional.Queue do
  @moduledoc """
  Named FIFO queue for executing commands.

  A queue must be first created, usually as a part of the supervision tree,
  using `start_link/1`. Commands are then enqueued using `enqueue/4`.

  The queue has a configured size, which determines the maximum number
  of commands that are executed simultaneously. Other commands wait in queue
  for an execution slot to open.
  """

  use GenServer

  alias VpsAdmin.Transactional

  @type name :: atom

  # Client API
  @spec start_link({name, integer}) :: GenServer.on_start
  def start_link({queue, size}) do
    GenServer.start_link(__MODULE__, {queue, size}, name: via_tuple(queue))
  end

  @spec enqueue(name, term, {atom, atom, list}, GenServer.server) :: :ok
  @doc """
  Add command to the queue.

  The command is identified by `id`. It can be any term, but you have to ensure
  its uniqueness. `mfa` is a tuple `{module, function, arguments}`. This
  function is called to execute the command. It has to return type
  `GenServer.on_start`. The process has to be started as linked.

  `parent` is a name of a process that is to be notified when the command
  is executed and when it finishes. Message `{:queue, id, :executing}` is sent
  when execution starts, message `{:queue, id, :done, exit_reason}` is sent
  when the executed process finishes with whatever reason. When the process
  cannot be started, message `{:queue, id, :error, error}` is sent.
  """
  def enqueue(queue, id, mfa, parent) do
    GenServer.call(via_tuple(queue), {:enqueue, id, mfa, parent})
  end

  def status(queue) do
    GenServer.call(via_tuple(queue), :status)
  end

  def via_tuple(name) do
    {:via, Registry, {Transactional.Registry, {:queue, name}}}
  end

  # Server implementation
  def init({name, size}) do
    Process.flag(:trap_exit, true)
    {:ok, %{name: name, size: size, executing: [], queued: :queue.new}}
  end

  def handle_call({:enqueue, id, mfa, parent}, _from, state) do
    state = if length(state.executing) < state.size do
      execute(state, id, mfa, parent)

    else
      do_enqueue(state, id, mfa, parent)
    end

    {:reply, :ok, state}
  end

  def handle_call(:status, _from, state) do
    {:reply, %{
      executing: length(state.executing),
      queued: :queue.len(state.queued),
      size: state.size,
    }, state}
  end

  def handle_info({:EXIT, pid, reason}, state) do
    state = case Enum.find(state.executing, nil, fn {p,_,_} -> p == pid end) do
      nil ->
        state

      {pid, id, parent} ->
        notify(parent, id, :done, reason)
        state.executing
        |> update_in(&List.delete(&1, {pid, id, parent}))
        |> run()
    end

    {:noreply, state}
  end

  defp execute(state, id, {m, f, a}, parent) do
    case apply(m, f, a) do
      {:ok, pid} ->
        Process.link(pid)
        notify(parent, id, :executing)
        update_in(state.executing, &[{pid, id, parent} | &1])

      {:error, error} ->
        notify(parent, id, :error, error)
        state
    end
  end

  defp do_enqueue(state, id, mfa, parent) do
    %{state | queued: :queue.in({id, mfa, parent}, state.queued)}
  end

  defp run(state) do
    if length(state.executing) < state.size do
      case :queue.out(state.queued) do
        {{:value, {id, mfa, parent}}, queue} ->
          %{state | queued: queue}
          |> execute(id, mfa, parent)
          |> run()

        {:empty, _queue} ->
          state
      end
    else
      state
    end
  end

  defp notify(parent, id, status, reason \\ nil) do
    if reason do
      GenServer.cast(parent, {:queue, id, status, reason})
    else
      GenServer.cast(parent, {:queue, id, status})
    end
  end
end
