defmodule VpsAdmin.Queue.Server do
  @moduledoc false

  use GenServer
  alias VpsAdmin.Queue

  ### Client API
  def start_link({queue, size}) do
    GenServer.start_link(__MODULE__, size, name: via_tuple(queue))
  end

  def enqueue(queue, id, mfa, parent, opts \\ []) do
    GenServer.call(via_tuple(queue), {:enqueue, id, mfa, parent, opts})
  end

  def reserve(queue, name, size, parent) do
    GenServer.call(via_tuple(queue), {:reserve, name, size, parent})
  end

  def release(queue, name, size) do
    GenServer.call(via_tuple(queue), {:release, name, size})
  end

  def status(queue) do
    GenServer.call(via_tuple(queue), :status)
  end

  defp via_tuple(name) do
    {:via, Registry, {Queue.Registry, {:queue, name}}}
  end

  ### Server implementation
  @impl true
  def init(size) do
    Process.flag(:trap_exit, true)
    {:ok, %{
      max_size: size,
      current_size: size,
      executing: [],
      queued: :queue.new(),
      reservations: %{}
    }}
  end

  @impl true
  def handle_call({:enqueue, id, mfa, parent, opts}, _from, state) do
    name = Keyword.get(opts, :name)
    arg = {id, mfa, parent}

    case {name, state.reservations[name]} do
      {nil, _size} ->
        {:reply, :ok, do_enqueue(state, state.current_size, arg)}

      {^name, size} ->
        {:reply, :ok, do_enqueue(state, state.current_size + size, arg)}
    end
  end

  def handle_call({:reserve, _n, size, _p}, _from, %{max_size: max_size} = state) when size > max_size or size < 1 do
    {:reply, {:error, :badreservation}, state}
  end

  def handle_call({:reserve, name, size, parent}, _from, %{max_size: max_size} = state) do
    case state.reservations[name] do
      v when is_nil(v) or (v + size) <= max_size ->
        state =
          if length(state.executing) + size <= state.current_size do
            do_reserve(state, name, size, parent)
          else
            do_enqueue_reservation(state, name, size, parent)
          end

        {:reply, :ok, state}

      _ ->
        {:reply, {:error, :badreservation}, state}
    end
  end

  def handle_call({:release, name, size}, _from, state) do
    case do_release(state, name, size) do
      {:ok, new_state} ->
        {:reply, :ok, process_next(new_state)}

      {:error, error} ->
        {:reply, {:error, error}, state}
    end
  end

  def handle_call(:status, _from, state) do
    {:reply,
     %{
       executing: length(state.executing),
       queued: :queue.len(state.queued),
       current_size: state.current_size,
       max_size: state.max_size,
       reservations: %{}
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
          |> process_next()
      end

    {:noreply, state}
  end

  defp do_execute(state, id, {m, f, a}, parent) do
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

  defp do_reserve(state, name, size, parent) do
    notify(parent, name, :reserved)

    state
    |> Map.update!(:current_size, &(&1 - size))
    |> Map.update!(:reservations, &add_reservation(&1, name, size))
  end

  defp add_reservation(reservations, name, size) do
    Map.update(reservations, name, size, &(&1 + size))
  end

  defp do_release(state, name, size) do
    case state.reservations[name] do
      nil ->
        {:error, :notfound}

      n when size > n or size < 1 ->
        {:error, :invalid}

      _n ->
        new_state =
          state
          |> Map.update!(:current_size, &(&1 + size))
          |> Map.update!(:reservations, &remove_reservation(&1, name, size))
        {:ok, new_state}
    end
  end

  defp remove_reservation(reservations, name, size) do
    case reservations[name] do
      n when n == size ->
        Map.delete(reservations, name)

      n when n > size ->
        Map.update!(reservations, name, &(&1 - size))
    end
  end

  defp do_enqueue(state, size, {id, mfa, parent}) do
    if length(state.executing) < size do
      do_execute(state, id, mfa, parent)
    else
      do_enqueue_runnable(state, id, mfa, parent)
    end
  end

  defp do_enqueue_runnable(state, id, mfa, parent) do
    %{state | queued: :queue.in({:run, {id, mfa, parent}}, state.queued)}
  end

  defp do_enqueue_reservation(state, name, size, parent) do
    %{state | queued: :queue.in({:reserve, {name, size, parent}}, state.queued)}
  end

  defp process_next(state) do
    if length(state.executing) < state.current_size do
      case :queue.peek(state.queued) do
        :empty ->
          state

        {:value, item} ->
          case process_item(state, item) do
            {:ok, state} ->
              process_next(state)
            {:error, state} ->
              state
          end
      end
    else
      state
    end
  end

  defp process_item(state, {:run, {id, mfa, parent}} = item) do
    {{:value, ^item}, new_queue} = :queue.out(state.queued)

    {
      :ok,
      state
      |> Map.put(:queued, new_queue)
      |> do_execute(id, mfa, parent)
    }
  end

  defp process_item(state, {:reserve, {name, size, parent}} = item) do
    if (state.current_size - length(state.executing)) >= size do
      {{:value, ^item}, new_queue} = :queue.out(state.queued)
      {
        :ok,
        state
        |> Map.put(:queued, new_queue)
        |> do_reserve(name, size, parent)
      }
    else
      {:error, state}
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
