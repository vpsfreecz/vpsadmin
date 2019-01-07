defmodule VpsAdmin.Supervisor.ChainPoller do
  use GenServer

  alias VpsAdmin.Supervisor.Convert
  alias VpsAdmin.Supervisor.Manager, as: MyManager
  alias VpsAdmin.Persistence.Query
  alias VpsAdmin.Transactional.Manager
  alias VpsAdmin.Worker

  ### Client interface
  def start_link(_arg) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  ### Server implementation
  def init(:ok) do
    {:ok, nil, 1000}
  end

  def handle_info(:timeout, nil) do
    {:noreply, run(Query.TransactionChain.get_open_ids(), nil), 1000}
  end

  def handle_info(:timeout, last_id) do
    {:noreply, run(Query.TransactionChain.get_open_ids_since(last_id), last_id), 1000}
  end

  defp run(chain_ids, last_id) do
    Enum.reduce(
      chain_ids,
      last_id,
      fn id, _acc ->
        Manager.add_transaction(id, MyManager, Worker)
        id
      end
    )
  end
end
