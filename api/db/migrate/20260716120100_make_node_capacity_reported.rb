class MakeNodeCapacityReported < ActiveRecord::Migration[8.1]
  def change
    change_column_default :nodes, :cpus, from: nil, to: 0
    change_column_default :nodes, :total_memory, from: nil, to: 0
    change_column_default :nodes, :total_swap, from: nil, to: 0
  end
end
