class AddNodeKernelConfigurations < ActiveRecord::Migration[8.1]
  def up
    change_column_null :node_current_statuses, :kernel, true

    create_table :node_kernel_configurations,
                 charset: 'utf8mb3',
                 collation: 'utf8mb3_bin' do |t|
      t.string :digest, limit: 64, null: false
      t.text :content, size: :medium, null: false
      t.timestamps null: false
    end

    add_index :node_kernel_configurations, :digest, unique: true

    create_table :node_kernel_configuration_options,
                 charset: 'utf8mb3',
                 collation: 'utf8mb3_bin' do |t|
      t.references :node_kernel_configuration,
                   null: false,
                   index: false,
                   foreign_key: { on_delete: :cascade }
      t.string :name, limit: 255, null: false
      t.text :value, null: false
    end

    add_index :node_kernel_configuration_options,
              %i[node_kernel_configuration_id name],
              unique: true,
              name: :idx_node_kernel_configuration_options_unique
    add_index :node_kernel_configuration_options,
              %i[name node_kernel_configuration_id],
              name: :idx_node_kernel_configuration_options_lookup
  end

  # MySQL uses the explicit composite option index for the foreign key. Rails'
  # inferred rollback removes that index first, so drop the tables before
  # restoring the legacy non-null status column.
  def down
    drop_table :node_kernel_configuration_options
    drop_table :node_kernel_configurations

    execute 'UPDATE node_current_statuses SET kernel = \'\' WHERE kernel IS NULL'
    change_column_null :node_current_statuses, :kernel, false
  end
end
