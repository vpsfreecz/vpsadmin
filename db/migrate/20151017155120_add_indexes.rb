class AddIndexes < ActiveRecord::Migration
  def change
    add_index :transaction_chains, :user_id
    add_index :transaction_chains, :user_session_id
    add_index :transactions, :transaction_chain_id
    add_index :transactions, :t_depends_on
    add_index :transaction_chain_concerns, :transaction_chain_id
    add_index :transaction_confirmations, :transaction_id
    add_index :port_reservations, :transaction_chain_id
    add_index :port_reservations, :node_id
    add_index :user_cluster_resources, :user_id
    add_index :user_cluster_resources, :environment_id
    add_index :user_cluster_resources, :cluster_resource_id
    add_index :cluster_resource_uses, :user_cluster_resource_id
    add_index :cluster_resource_uses, %i(class_name table_name row_id),
              name: :cluster_resouce_use_name_search
    add_index :datasets, :user_id
    add_index :dataset_in_pools, :dataset_id
    add_index :dataset_properties, :dataset_id
    add_index :dataset_trees, :dataset_in_pool_id
    add_index :branches, :dataset_tree_id
    add_index :snapshots, :dataset_id
    add_index :snapshot_in_pools, :snapshot_id
    add_index :snapshot_in_pools, :dataset_in_pool_id
    add_index :snapshot_in_pool_in_branches, :snapshot_in_pool_id
    add_index :mounts, :vps_id
    add_index :vps, :m_id
    add_index :vps, :vps_server
    add_index :vps_features, :vps_id
    add_index :vps_has_config, :vps_id
    add_index :vps_ip, :vps_id
    add_index :vps_ip, :user_id
    add_index :vps_ip, :ip_location
    add_index :user_sessions, :user_id
    add_index :mail_logs, :user_id
    add_index :object_states, %i(class_name row_id)
    add_index :transfered, %i(tr_ip tr_date)
    add_index :transfered, %i(tr_ip)
  end
end
