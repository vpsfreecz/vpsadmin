class AddOsctlSupport < ActiveRecord::Migration
  class UserNamespaceBlock < ActiveRecord::Base ; end
  class UserNamespaceUgid < ActiveRecord::Base ; end
  class OsTemplate < ActiveRecord::Base ; end

  def change
    create_table :user_namespaces do |t|
      t.references :user,                null: false
      t.references :user_namespace_ugid, null: false
      t.integer    :block_count,         null: false
      t.integer    :offset,              null: false, unsigned: true
      t.integer    :size,                null: false
    end

    add_index :user_namespaces, :user_id
    add_index :user_namespaces, :user_namespace_ugid_id, unique: true
    add_index :user_namespaces, :block_count
    add_index :user_namespaces, :offset
    add_index :user_namespaces, :size

    create_table :user_namespace_blocks do |t|
      t.references :user_namespace,      null: true
      t.integer    :index,               null: false
      t.integer    :offset,              null: false, unsigned: true
      t.integer    :size,                null: false
    end

    add_index :user_namespace_blocks, :user_namespace_id
    add_index :user_namespace_blocks, :index, unique: true
    add_index :user_namespace_blocks, :offset

    reversible do |dir|
      dir.up do
        size = 2**16
        max = 2**32
        i = 1
        offset = size * 2

        while offset < max
          UserNamespaceBlock.create!(
              index: i,
              offset: offset,
              size: size,
          )

          i += 1
          offset += size
        end
      end
    end

    create_table :user_namespace_ugids do |t|
      t.references :user_namespace,      null: true
      t.integer    :ugid,                null: false, unsigned: true
    end

    add_index :user_namespace_ugids, :user_namespace_id, unique: true
    add_index :user_namespace_ugids, :ugid, unique: true

    reversible do |dir|
      dir.up do
        10000.times do |i|
          UserNamespaceUgid.create!(ugid: 10000+i)
        end
      end
    end

    add_column :nodes, :hypervisor_type, :integer, null: true
    add_index :nodes, :hypervisor_type

    reversible do |dir|
      dir.up do
        ActiveRecord::Base.connection.execute(
            'UPDATE nodes SET hypervisor_type = 0 WHERE role = 0'
        )
      end
    end

    add_column :dataset_in_pools, :user_namespace_id, :integer, null: true
    add_index :dataset_in_pools, :user_namespace_id

    add_column :vpses, :veth_name, :string, limit: 30, null: false, default: 'venet0'
    add_index :vpses, :veth_name

    add_column :os_templates, :vendor, :string
    add_column :os_templates, :variant, :string
    add_column :os_templates, :arch, :string
    add_column :os_templates, :distribution, :string
    add_column :os_templates, :version, :string

    reversible do |dir|
      dir.up do
        OsTemplate.all.each do |t|
          dist, ver, arch, vendor, variant = t.name.split('-')

          t.update!(
              distribution: dist,
              version: ver,
              arch: arch,
              vendor: vendor,
              variant: variant,
          )
        end
      end
    end
  end
end
