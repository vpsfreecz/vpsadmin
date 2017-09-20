class RemoveUserPlaygroundEnabled < ActiveRecord::Migration
  def change
    remove_column :members, :m_playground_enable, :boolean, null: false, default: true
  end
end
