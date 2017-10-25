defmodule VpsAdmin.Transactional.Chain.Controller do
  @moduledoc """
  A process running on all nodes handling new chains.

  Whenever a chain is created and executed, `new/1` is called. A message
  is sent to all nodes that are involved in execution of the chain.
  Controllers running on such nodes then start a process for the chain under the
  `VpsAdmin.Transactional.Chain.Supervisor` supervisor.
  """

  use GenServer
  require Logger

  alias VpsAdmin.Transactional.{Chain, State, Transaction}

  # Client API
  def start_link(_args) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @spec new(chain :: Chain.t) :: :ok
  def new(chain) do
    Logger.debug "Announcing chain #{chain.id}"

    {_replies, _bad_nodes} = GenServer.multi_call(
      chain.nodes,
      __MODULE__,
      {:new, chain},
      15000
    )

    :ok
  end

  # Server implementation
  def init(nil) do
    {:ok, nil}
  end

  def handle_call({:new, chain}, _from, state) do
    Logger.debug "Starting processes for chain #{chain.id}"

    {:ok, _pid} = State.Supervisor.add_chain(chain)
    {:ok, _pid} = Chain.Supervisor.add_chain(chain.id)

    {:reply, :ok, state}
  end
end
