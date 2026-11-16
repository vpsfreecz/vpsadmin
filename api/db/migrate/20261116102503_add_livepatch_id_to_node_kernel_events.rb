class AddLivepatchIdToNodeKernelEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :node_kernel_events, :livepatch_id, :string, limit: 63, null: true
  end
end
