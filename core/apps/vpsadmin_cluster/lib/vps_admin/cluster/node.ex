defmodule VpsAdmin.Cluster.Node do
  def self_id() do
    Application.fetch_env!(:vpsadmin_cluster, :node_id)
  end
end
