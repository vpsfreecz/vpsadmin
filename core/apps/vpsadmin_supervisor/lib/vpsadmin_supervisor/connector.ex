defmodule VpsAdmin.Supervisor.Connector do
  use GenServer

  alias VpsAdmin.Persistence
  alias VpsAdmin.Supervisor.Convert

  @timeout 60000

  def start_link(_args) do
    GenServer.start_link(__MODULE__, [])
  end

  def init(_args) do
    {:ok, nil, {:continue, :startup}}
  end

  def handle_continue(:startup, nil) do
    do_connect()
    {:noreply, nil, @timeout}
  end

  def handle_info(:timeout, nil) do
    do_connect()
    {:noreply, nil, @timeout}
  end

  defp do_connect do
    self_node = node()

    Persistence.Query.Node.list
    |> Enum.map(&Convert.DbToRuntime.node/1)
    |> Enum.each(fn
         ^self_node ->
           :ok
         n ->
           Node.connect(n)
       end)
  end
end
