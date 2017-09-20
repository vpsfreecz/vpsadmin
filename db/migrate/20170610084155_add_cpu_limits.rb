class AddCpuLimits < ActiveRecord::Migration
  def change
    add_column :vpses, :cpu_limit, :integer, null: true
  end
end
