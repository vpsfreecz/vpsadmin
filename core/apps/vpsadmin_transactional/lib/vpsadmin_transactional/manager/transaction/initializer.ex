defmodule VpsAdmin.Transactional.Manager.Transaction.Initializer do
  use GenServer, restart: :transient

  alias VpsAdmin.Transactional.Manager.Transaction

  ### Client interface
  def start_link({manager, worker}) do
    GenServer.start_link(__MODULE__, {manager, worker})
  end

  ### Server implementation
  @impl true
  def init({manager, worker}) do
    {:ok, {manager, worker}, {:continue, :startup}}
  end

  @impl true
  def handle_continue(:startup, {manager, worker} = state) do
    case manager.open_transactions() do
      ts when is_list(ts) ->
        Enum.each(
          ts,
          &Transaction.Supervisor.add_transaction(&1, manager, worker)
        )

        {:stop, :normal, state}

      {:error, reason} ->
        {:stop, reason, state}
    end
  end
end
