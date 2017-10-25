defmodule VpsAdmin.Cluster.Node do
  def self_id() do
    Application.fetch_env!(:vpsadmin_cluster, :node_id)
  end

  def erlang_node(node), do: :"#{node.name}@#{node.ip_addr}"
end
