defmodule VpsAdmin.Transactional.Command do
  use GenServer

  alias VpsAdmin.Transactional

  @enforce_keys [:id, :state, :node, :module, :params]
  defstruct [:id, :state, :node, :module, :params]

  @type t :: %__MODULE__{
    id: integer,
    node: atom,
    module: String.t,
    params: map,
  }

  @type params :: map

  @callback execute(params :: params) :: :ok
  @callback rollback(params :: params) :: :ok

  def new(id, state, node, module, params) do
    %__MODULE__{
      id: id,
      state: state,
      node: node,
      module: module,
      params: params,
    }
  end

  def start_link(chain_id, transaction_id, cmd_id) do
    GenServer.start_link(
      __MODULE__,
      {chain_id, transaction_id, cmd_id},
      name: via_tuple(cmd_id)
    )
  end

  def via_tuple(cmd_id) when is_integer(cmd_id) do
    {:via, Registry, {Transactional.Registry, {:command, cmd_id}}}
  end

  def init({chain_id, transaction_id, cmd_id}) do
    send(self(), :cmd_startup)
    {:ok, Transactional.State.get_command(chain_id, transaction_id, cmd_id)}
  end

  def handle_info(:cmd_startup, %{state: :executing} = cmd) do
    apply(cmd.module, :execute, [cmd.params])
    {:stop, :normal, cmd}
  end

  def handle_info(:cmd_startup, %{state: :rollingback} = cmd) do
    apply(cmd.module, :rollback, [cmd.params])
    {:stop, :normal, cmd}
  end
end
