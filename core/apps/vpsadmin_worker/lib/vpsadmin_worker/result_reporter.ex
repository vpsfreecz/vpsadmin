defmodule VpsAdmin.Worker.ResultReporter do
  use GenServer

  alias VpsAdmin.Worker.Distributor

  def report({t, cmd} = arg) do
    {:ok, pid} = GenServer.start_link(__MODULE__, :ok)
    GenServer.call(pid, {:report, arg}, 10_000)
  end

  @impl true
  def init(:ok) do
    {:ok, nil}
  end

  @impl true
  def handle_call({:report, {t, cmd}}, _from, nil) do
    reply =
      try do
        Distributor.report_result({t, cmd})
      catch
        :exit, {:timeout, _} ->
          {:error, :timeout}
      end

    {:stop, :normal, reply, nil}
  end
end
