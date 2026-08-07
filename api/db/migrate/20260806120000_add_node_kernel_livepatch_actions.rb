class AddNodeKernelLivepatchActions < ActiveRecord::Migration[8.1]
  def change
    add_column :node_kernel_events, :livepatch_action, :integer, null: true
  end
end
