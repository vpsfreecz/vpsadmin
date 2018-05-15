class MakeClusterResourceValuesDecimal < ActiveRecord::Migration
  def up
    change_column :cluster_resources, :min, :decimal, precision: 40, scale: 0, null: false
    change_column :cluster_resources, :max, :decimal, precision: 40, scale: 0, null: false
    change_column :user_cluster_resources, :value, :decimal, precision: 40, scale: 0, null: false
    change_column :cluster_resource_uses, :value, :decimal, precision: 40, scale: 0, null: false
    change_column :default_object_cluster_resources, :value, :decimal, precision: 40, scale: 0, null: false
  end

  def down
    change_column :cluster_resources, :min, :integer, null: false
    change_column :cluster_resources, :max, :integer, null: false
    change_column :user_cluster_resources, :value, :integer, null: false
    change_column :cluster_resource_uses, :value, :integer, null: false
    change_column :default_object_cluster_resources, :value, :integer, null: false
  end
end
