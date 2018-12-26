defmodule VpsAdmin.Queue.Server do
  @moduledoc false

  use GenServer
  alias VpsAdmin.Queue

  ### Client API
  def start_link({queue, size}) do
    GenServer.start_link(__MODULE__, {queue, size}, name: via_tuple(queue))
  end

  def enqueue(queue, id, mfa, parent) do
    GenServer.call(via_tuple(queue), {:enqueue, id, mfa, parent})
  end

  def status(queue) do
    GenServer.call(via_tuple(queue), :status)
  end

  def via_tuple(name) do
    {:via, Registry, {Queue.Registry, {:queue, name}}}
  end

  ### Server implementation
  @impl true
  def init({name, size}) do
    Process.flag(:trap_exit, true)
    {:ok, %{name: name, size: size, executing: [], queued: :queue.new()}}
  end

  @impl true
  def handle_call({:enqueue, id, mfa, parent}, _from, state) do
    state =
      if length(state.executing) < state.size do
        execute(state, id, mfa, parent)
      else
        do_enqueue(state, id, mfa, parent)
      end

    {:reply, :ok, state}
  end

  def handle_call(:status, _from, state) do
    {:reply,
     %{
       executing: length(state.executing),
       queued: :queue.len(state.queued),
       size: state.size
     }, state}
  end

  @impl true
  def handle_info({:EXIT, pid, reason}, state) do
    state =
      case Enum.find(state.executing, nil, fn {p, _, _} -> p == pid end) do
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
