defmodule VpsAdmin.Persistence.Transaction.Processes do
  @moduledoc """
  Tracks processes that are currently working within a transaction chain.

  Such processes are auto-scoped by `VpsAdmin.Persistence` to see latest
  data changed by the corresponding chain. Other processes see latest
  confirmed data. PIDs of processes that are running inside a transaction
  chain are stored in ETS owned by this server.

  Processes running inside transaction chain are linked with this server
  to ensure that if the server crashes, all processes crash also. This is
  necessary, because when the server crashes, the ETS table with the state
  is gone and imprecise values would be returned after restart.
  The server is trapping exits, so it does not exit when transaction process
  crashes.
  """

  use GenServer

  require Logger

  # Client API
  def start_link do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def add(pid, chain_id) do
    GenServer.call(__MODULE__, {:add, pid, chain_id})
  end

  def remove(pid) do
    GenServer.call(__MODULE__, {:remove, pid})
  end

  def chain_id, do: chain_id(self())

  def chain_id(pid) do
    case :ets.lookup(__MODULE__, pid) do
      [{^pid, chain_id}] -> chain_id
      _ -> nil
    end
  end

  # Server implementation
  def init([]) do
    Process.flag(:trap_exit, true)
    :ets.new(__MODULE__, [:named_table])
    {:ok, nil}
  end

  def handle_call({:add, pid, chain_id}, _from, _state) do
    case chain_id(pid) do
      nil -> monitor(pid, chain_id)
      _chain_id -> {:reply, :ok, nil}
    end
  end

  def handle_call({:remove, pid}, _from, _state) do
    :ets.delete(__MODULE__, pid)
    Process.unlink(pid)
    {:reply, :ok, nil}
  end

  def handle_info({:EXIT, from, reason}, state) do
    Logger.debug "Linked process #{inspect(from)} exited with #{reason}"
    :ets.delete(__MODULE__, from)
    {:noreply, nil}
  end

  defp monitor(pid, chain_id) do
    :ets.insert(__MODULE__, {pid, chain_id})
    Process.link(pid)
    {:reply, :ok, nil}
  end
end
