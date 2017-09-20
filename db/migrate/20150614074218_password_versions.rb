class PasswordVersions < ActiveRecord::Migration
  class User < ActiveRecord::Base
    self.table_name = 'members'
    self.primary_key = 'm_id'
  end

  def change
    add_column :members, :password_version, :integer, null: false, default: 0
    change_column :members, :password_version, :integer, null: false, default: 1
  end
end
