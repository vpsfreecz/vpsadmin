class AddIpRanges < ActiveRecord::Migration
  def change
    add_column :networks, :type, :string, limit: 255, null: false
    add_column :networks, :ancestry, :string, null: true, limit: 255
    add_column :networks, :ancestry_depth, :integer, null: false, default: 0
    add_column :networks, :split_access, :integer, null: false, default: 0
    add_column :networks, :split_prefix, :integer, null: true
    add_column :networks, :user_id, :integer, null: true

    reversible do |dir|
      dir.up do
        ActiveRecord::Base.connection.execute(
            "UPDATE networks SET `type` = 'Network'"
        )
      end
    end
  end
end
