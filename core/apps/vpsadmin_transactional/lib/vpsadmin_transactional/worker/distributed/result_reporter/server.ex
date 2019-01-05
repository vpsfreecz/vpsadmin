defmodule VpsAdmin.Transactional.Worker.Distributed.ResultReporter.Server do
  use GenServer, restart: :transient

  require Logger
  alias VpsAdmin.Transactional.Worker.Distributed.Distributor

  @retry 1_000

  ### Client interface
  def start_link({t, cmd} = arg) do
    GenServer.start_link(__MODULE__, arg, name: __MODULE__)
  end

  ### Server implementation
  @impl true
  def init({t, cmd} = arg) do
    {:ok, arg, {:continue, :startup}}
  end

  @impl true
  def handle_continue(:startup, {_t, _cmd} = state) do
    work(state)
  end

  @impl true
  def handle_info(:retry, {_t, _cmd} = state) do
    work(state)
  end

  defp work(state) do
    if report(state) do
      {:stop, :normal, state}
    else
      {:noreply, state}
    end
  end

  defp report({t, cmd}) do
    try do
      Distributor.report_result({t, cmd})
      true

    catch
      :exit, {{:nodedown, _}, _} ->
        retry({t, cmd})
        false

      :exit, {:noproc, _} ->
        retry({t, cmd})
        false
    end
  end

  defp retry({t, cmd}) do
    Logger.debug("Failed to report result of #{t}:#{cmd.id}, retry in #{@retry}ms")
    Process.send_after(self(), :retry, @retry)
  end
end
