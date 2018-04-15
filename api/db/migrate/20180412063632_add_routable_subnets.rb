class AddRoutableSubnets < ActiveRecord::Migration
  def change
    remove_column :networks, :type, :string, limit: 255, null: false, default: 'Network'
    remove_column :networks, :ancestry, :string, null: true, limit: 255
    remove_column :networks, :ancestry_depth, :integer, null: false, default: 0
    remove_column :networks, :user_id, :integer, null: true

    add_column :ip_addresses, :prefix, :integer, null: true
    add_column :ip_addresses, :size, 'bigint unsigned', null: true

    reversible do |dir|
      dir.up do
        ActiveRecord::Base.connection.execute(
          'UPDATE networks
          SET split_prefix = (
            CASE ip_version
            WHEN 4 THEN 32
            WHEN 6 THEN 128
            END
          )
          WHERE split_prefix IS NULL'
        )

        ActiveRecord::Base.connection.execute(
          'UPDATE ip_addresses a
          INNER JOIN networks n ON n.id = a.network_id
          SET a.prefix = (
            CASE n.ip_version
            WHEN 4 THEN 32
            WHEN 6 THEN 128
            END
          )
        ')

        ActiveRecord::Base.connection.execute(
          'UPDATE ip_addresses SET size = 1'
        )
      end
    end

    change_column_null :networks, :split_prefix, false
    change_column_null :ip_addresses, :prefix, false
    change_column_null :ip_addresses, :size, false
  end
end
