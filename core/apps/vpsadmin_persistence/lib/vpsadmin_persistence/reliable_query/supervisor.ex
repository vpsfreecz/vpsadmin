defmodule VpsAdmin.Persistence.ReliableQuery.Supervisor do
  use GenServer
  require Logger

  ### Client interface
  def start_link(_arg) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def run(func) do
    run(func, :infinity)
  end

  def run(func, :infinity = timeout) do
    GenServer.call(__MODULE__, {:run, func, timeout}, timeout)
  end

  def run(func, timeout) do
    GenServer.call(__MODULE__, {:run, func, timeout}, timeout+250)
  end

  ### Server implementation
  @impl true
  def init(:ok) do
    Process.flag(:trap_exit, true)
    {:ok, nil}
  end

  @impl true
  def handle_call({:run, func, timeout}, _from, state) do
    run_task(func, timeout, state)
  end

  @impl true
  def handle_info({:EXIT, _pid, _reason}, state) do
    {:noreply, state}
  end

  defp run_task(func, timeout, state) do
    t1 = NaiveDateTime.utc_now()
    task = Task.async(func)

    case Task.yield(task, timeout) do
      {:ok, v} ->
        {:reply, v, state}

      {:exit, :normal} ->
        {:reply, :ok, state}

      {:exit, _reason} ->
        Logger.debug("Task failed, restarting")
        t2 = NaiveDateTime.utc_now()

        case new_timeout(t1, t2, timeout) do
          {:error, :timeout} =v ->
            {:reply, v, state}

          {:ok, timeout} ->
            run_task(func, timeout, state)
        end
    end
  end

  defp new_timeout(_t1, _t2, :infinity), do: {:ok, :infinity}

  defp new_timeout(t1, t2, timeout) do
    diff = NaiveDateTime.diff(t2, t1, :microseconds)

    if timeout > diff do
      {:ok, timeout - diff}
    else
      {:error, :timeout}
    end
  end
end
