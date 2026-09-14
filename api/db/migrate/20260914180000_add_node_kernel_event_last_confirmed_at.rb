class AddNodeKernelEventLastConfirmedAt < ActiveRecord::Migration[8.1]
  def change
    add_column :node_kernel_events, :last_confirmed_at, :datetime, null: true
  end
end
