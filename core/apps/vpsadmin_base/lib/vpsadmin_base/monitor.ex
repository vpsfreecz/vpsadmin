defmodule VpsAdmin.Base.Monitor do
  use GenServer

  @type monitor :: GenServer.server()
  @type event :: term
  @type arg :: term

  ### Client interface
  @spec start_link([...]) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start(__MODULE__, :ok, opts)
  end

  @spec subscribe(monitor, event) :: :ok
  def subscribe(monitor, event) do
    GenServer.call(monitor, {:subscribe, event, self()})
  end

  @spec unsubscribe(monitor, event) :: :ok
  def unsubscribe(monitor, event) do
    GenServer.call(monitor, {:unsubscribe, event, self()})
  end

  @spec read_one(monitor) :: {event, arg}
  def read_one(monitor) do
    GenServer.call(monitor, {:read_one, self()})
  end

  @spec publish(monitor, event, arg) :: :ok
  def publish(monitor, event, arg) do
    GenServer.cast(monitor, {:publish, event, arg})
  end

  @spec subscribers(monitor) :: [{event, Process.dest()}]
  def subscribers(monitor) do
    GenServer.call(monitor, :subscribers)
  end

  ### Server implementation
  @impl true
  def init(:ok) do
    {:ok, %{listeners: [], readers: [], queue: %{}}}
  end

  @impl true
  def handle_call({:subscribe, event, proc}, _from, state) do
    {:reply, :ok, do_subscribe(state, event, proc)}
  end

  def handle_call({:unsubscribe, event, proc}, _from, state) do
    {:reply, :ok, do_unsubscribe(state, event, proc)}
  end

  def handle_call({:read_one, proc}, from, state) do
    case do_read(state.queue, proc) do
      {queue, nil} ->
        {:noreply, %{state | readers: state.readers ++ [{proc, from}], queue: queue}}

      {queue, msg} ->
        {:reply, msg, %{state | queue: queue}}
    end
  end

  def handle_call(:subscribers, _from, state) do
    {
      :reply,
      Enum.map(state.listeners, fn {event, proc, _ref} -> {event, proc} end),
      state
    }
  end

  @impl true
  def handle_cast({:publish, event, arg}, state) do
    {:noreply, do_publish(state, event, arg)}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, object, _reason}, state) do
    {:noreply, do_unsubscribe(state, {ref, object})}
  end

  defp do_subscribe(state, event, proc) do
    %{state
      | listeners: [{event, proc, Process.monitor(proc)} | state.listeners]}
  end

  defp do_unsubscribe(state, event, proc) do
    %{
      state
      | listeners:
          Enum.reject(
            state.listeners,
            fn
              {^event, ^proc, _ref} -> true
              _ -> false
            end
          )
    }
  end

  defp do_unsubscribe(state, {ref, proc}) do
    %{
      state
      | listeners:
          Enum.reject(
            state.listeners,
            fn
              {_event, ^proc, ^ref} -> true
              _ -> false
            end
          )
    }
  end

  defp do_publish(state, event, arg) do
    {new_readers, new_queue} = Enum.reduce(
      state.listeners,
      {state.readers, state.queue},
      fn
        {^event, proc, _ref}, {readers, queue} ->
          case Enum.find(readers, fn {proc2, _from} -> proc == proc2 end) do
            nil ->
              {
                readers,
                Map.update(queue, proc, [{event, arg}], &(&1 ++ [{event, arg}]))
              }

            {_proc, from} = reader ->
              GenServer.reply(from, {event, arg})
              {List.delete(readers, reader), queue}
          end

        _, acc ->
          acc
      end
    )

    %{state | readers: new_readers, queue: new_queue}
  end

  defp do_read(queue, proc) do
    if Map.has_key?(queue, proc) do
      case queue[proc] do
        [h] ->
          {Map.delete(queue, proc), h}
        [h|t] ->
          {Map.put(queue, proc, t), h}
      end
    else
      {queue, nil}
    end
  end
end
