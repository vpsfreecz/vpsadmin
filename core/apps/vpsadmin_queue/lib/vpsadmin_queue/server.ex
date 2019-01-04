defmodule VpsAdmin.Queue.Server do
  @moduledoc false

  use GenServer
  alias VpsAdmin.Queue

  defmodule Item do
    defstruct ~w(type id mfa parent order urgent priority size)a

    def compare(item1, item2) do
      [!item1.urgent, item1.priority, item1.order] \
      <= \
      [!item2.urgent, item2.priority, item2.order]
    end
  end

  ### Client API
  def start_link({queue, size}) do
    GenServer.start_link(__MODULE__, {size, 0}, name: via_tuple(queue))
  end

  def start_link({queue, size, urgent}) do
    GenServer.start_link(__MODULE__, {size, urgent}, name: via_tuple(queue))
  end

  def enqueue(queue, id, mfa, parent, opts \\ []) do
    GenServer.call(via_tuple(queue), {:enqueue, id, mfa, parent, opts})
  end

  def reserve(queue, name, size, parent, opts \\ []) do
    GenServer.call(via_tuple(queue), {:reserve, name, size, parent, opts})
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
  def init({size, urgent}) do
    {:ok, %{
      max_size: size,
      max_urgent: urgent,
      current_size: size,
      executing: [],
      queued: [],
      reservations: %{},
      counter: 0
    }}
  end

  @impl true
  def handle_call({:enqueue, id, mfa, parent, opts}, _from, state) do
    name = Keyword.get(opts, :name)
    urgent = Keyword.get(opts, :urgent, false)
    prio = Keyword.get(opts, :priority, 0)
    arg = {id, mfa, parent, urgent, prio}
    urgent_size = state.current_size + state.max_urgent

    case {name, state.reservations[name], urgent} do
      {nil, _size, false} ->
        {:reply, :ok, do_enqueue_runnable(state, state.current_size, arg)}

      {nil, _size, true} ->
        {:reply, :ok, do_enqueue_runnable(state, urgent_size, arg)}

      {^name, nil, false} ->
        {:reply, :ok, do_enqueue_runnable(state, state.current_size, arg)}

      {^name, nil, true} ->
        {:reply, :ok, do_enqueue_runnable(state, urgent_size, arg)}

      {^name, size, false} ->
        {:reply, :ok, do_enqueue_runnable(state, state.current_size + size, arg)}

      {^name, size, true} ->
        {:reply, :ok, do_enqueue_runnable(state, urgent_size + size, arg)}
    end
  end

  def handle_call({:reserve, _n, size, _p, _o}, _from, state) when size < 1 do
    {:reply, {:error, :badreservation}, state}
  end

  def handle_call({:reserve, name, size, parent, opts}, _from, %{max_size: max_size} = state) do
    urgent = Keyword.get(opts, :urgent, false)
    prio = Keyword.get(opts, :priority, 0)
    max_urgent = state.max_size + state.max_urgent
    urgent_size = state.current_size + state.max_urgent

    case {state.reservations[name], urgent} do
      {v, false} when (is_nil(v) and size <= max_size) or (v + size) <= max_size ->
        state =
          if length(state.executing) + size <= state.current_size do
            do_reserve(state, name, size, parent)
          else
            do_enqueue_reservation(state, name, size, parent, urgent, prio)
          end

        {:reply, :ok, state}

      {v, true} when (is_nil(v) and size <= max_urgent) or (v + size) <= max_urgent ->
        state =
          if length(state.executing) + size <= urgent_size do
            do_reserve(state, name, size, parent)
          else
            do_enqueue_reservation(state, name, size, parent, urgent, prio)
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
       queued: length(state.queued),
       current_size: (if state.current_size < 0, do: 0, else: state.current_size),
       max_size: state.max_size,
       urgent_size: state.max_urgent,
       reservations: %{}
     }, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, object, reason}, state) do
    item = Enum.find(state.executing, fn
      {^object, ^ref, _id, _parent} -> true
      _ -> false
    end)

    new_state =
      case item do
        {^object, ^ref, id, parent} ->
          notify(parent, id, :done, reason)

          state.executing
          |> update_in(&List.delete(&1, item))
          |> process_next()

        nil ->
          state
      end

    {:noreply, new_state}
  end

  defp do_execute(state, id, {m, f, a}, parent) do
    case apply(m, f, a) do
      {:ok, pid} ->
        ref = Process.monitor(pid)
        notify(parent, id, :executing)
        update_in(state.executing, &[{pid, ref, id, parent} | &1])

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

  defp do_enqueue_runnable(state, size, {id, mfa, parent, urgent, prio}) do
    if length(state.executing) < size do
      do_execute(state, id, mfa, parent)
    else
      do_enqueue_item(state, %Item{
        type: :runnable,
        id: id,
        mfa: mfa,
        parent: parent,
        urgent: urgent,
        priority: prio
      })
    end
  end

  defp do_enqueue_reservation(state, name, size, parent, urgent, prio) do
    do_enqueue_item(state, %Item{
      type: :reservation,
      id: name,
      size: size,
      parent: parent,
      urgent: urgent,
      priority: prio
    })
  end

  defp do_enqueue_item(state, item) do
    new_state = Map.update!(state, :counter, &(&1 + 1))
    new_item = %{item | order: new_state.counter}
    Map.update!(new_state, :queued, &make_queue([new_item|&1]))
  end

  defp make_queue(list) do
    Enum.sort(list, &Item.compare/2)
  end

  defp process_next(state) do
    if length(state.executing) < state.current_size do
      case state.queued do
        [] ->
          state

        [h|_t] ->
          case process_item(state, h) do
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

  defp process_item(state, %Item{type: :runnable} = item) do
    [^item|new_queue] = state.queued

    {
      :ok,
      state
      |> Map.put(:queued, make_queue(new_queue))
      |> do_execute(item.id, item.mfa, item.parent)
    }
  end

  defp process_item(state, %Item{type: :reservation} = item) do
    if (state.current_size - length(state.executing)) >= item.size do
      [^item|new_queue] = state.queued

      {
        :ok,
        state
        |> Map.put(:queued, make_queue(new_queue))
        |> do_reserve(item.id, item.size, item.parent)
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
