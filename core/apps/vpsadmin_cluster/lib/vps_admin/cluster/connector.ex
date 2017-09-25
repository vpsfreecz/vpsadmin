defmodule VpsAdmin.Cluster.Connector do
  use GenServer, restart: :transient

  def start_link(_args) do
    GenServer.start_link(__MODULE__, [])
  end

  def init(_args) do
    send(self(), :startup)
    {:ok, nil}
  end

  def handle_info(:startup, nil) do
    for n <- VpsAdmin.Cluster.Query.Node.get_other_nodes() do
      Node.connect(:"#{n.name}@#{n.ip_addr}")
    end

    {:stop, :normal, nil}
  end
end
