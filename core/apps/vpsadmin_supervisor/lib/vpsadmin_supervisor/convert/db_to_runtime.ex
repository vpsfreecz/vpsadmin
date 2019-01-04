defmodule VpsAdmin.Supervisor.Convert.DbToRuntime do
  alias VpsAdmin.Transactional
  import Kernel, except: [node: 0, node: 1]

  def chain_to_transaction(chain) do
    %Transactional.Transaction{
      id: chain.id,
      state: chain.state
    }
  end

  def transaction_to_command(trans) do
    {state, status} = transaction_state(trans.done, trans.status)

    %Transactional.Command{
      id: trans.id,
      node: node(trans.node),
      queue: :default,
      reversible: trans.reversible,
      state: state,
      status: status,
      input: %{
        handle: trans.handle,
        priority: trans.priority,
        input: add_vps_id(trans.input, trans.vps_id)
      },
      output: %{}
    }
  end

  def transaction_state(:waiting, _status), do: {:queued, nil}
  def transaction_state(:executed, :failed), do: {:executed, :failed}
  def transaction_state(:executed, :done), do: {:executed, :done}
  def transaction_state(:executed, :warning), do: {:executed, :done}
  def transaction_state(:rolledback, :failed), do: {:rolledback, :failed}
  def transaction_state(:rolledback, :done), do: {:rolledback, :done}
  def transaction_state(:rolledback, :warning), do: {:rolledback, :done}

  def node(node), do: :"vpsadmin@#{node.fqdn}"

  defp add_vps_id(input, nil), do: input
  defp add_vps_id(input, id), do: Map.put(input, :vps_id, id)
end
