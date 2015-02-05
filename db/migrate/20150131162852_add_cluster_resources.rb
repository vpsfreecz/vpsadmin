class AddClusterResources < ActiveRecord::Migration
  class ClusterResource < ActiveRecord::Base
    enum resource_type: %i(numeric object)
  end

  def change
    remove_column :locations, :environment_id, :integer, null: true
    add_column :servers, :environment_id, :integer, null: false

    create_table :cluster_resources do |t|
      t.string       :name,                 null: false, limit: 100
      t.string       :label,                null: false, limit: 100
      t.integer      :min,                  null: false
      t.integer      :max,                  null: false
      t.integer      :stepsize,             null: false
      t.integer      :resource_type,        null: false
      t.string       :allocate_chain,       null: true
      t.string       :free_chain,           null: true
    end

    add_index :cluster_resources, :name, unique: true

    create_table :user_cluster_resources do |t|
      # Null user means it's a default resource value that
      # is given to new users.
      t.references   :user,                 null: true
      t.references   :environment,          null: false
      t.references   :cluster_resource,     null: false
      t.integer      :value,                null: false
    end

    add_index :user_cluster_resources, [:user_id, :environment_id, :cluster_resource_id],
              unique: true, name: :user_cluster_resource_unique

    create_table :cluster_resource_uses do |t|
      t.references   :user_cluster_resource, null: false
      t.string       :class_name,           null: false, limit: 255
      t.string       :table_name,           null: false, limit: 255
      t.integer      :row_id,               null: false
      t.integer      :value,                null: false
      t.integer      :confirmed,            null: false, default: 0
    end

    create_table :default_object_cluster_resources do |t|
      t.references   :environment,          null: false
      t.references   :cluster_resource,     null: false
      t.string       :class_name,           null: false, limit: 255
      t.integer      :value,                null: false
    end

    reversible do |dir|
      dir.up do
        ClusterResource.create!(
            name: :memory,
            label: 'Memory',
            min: 1*1024, # 1 GB
            max: 12*1024, # 12 GB
            stepsize: 1*1024, # 1 GB
            resource_type: :numeric
        )

        ClusterResource.create!(
            name: :swap,
            label: 'Swap',
            min: 0, # 1 GB
            max: 12*1024, # 12 GB
            stepsize: 1*1024, # 1 GB
            resource_type: :numeric
        )

        ClusterResource.create!(
            name: :cpu,
            label: 'CPU',
            min: 1,
            max: 8,
            stepsize: 1,
            resource_type: :numeric
        )

        ClusterResource.create!(
            name: :diskspace,
            label: 'Disk space',
            min: 10*1024, # 10 GB
            max: 2000*1024, # 2 TB
            stepsize: 10*1024, # 10 GB
            resource_type: :numeric
        )

        ClusterResource.create!(
            name: :ipv4,
            label: 'IPv4 address',
            min: 0,
            max: 4,
            stepsize: 1,
            resource_type: :object,
            allocate_chain: 'Ip::Allocate',
            free_chain: 'Ip::Free'
        )

        ClusterResource.create!(
            name: :ipv6,
            label: 'IPv6 address',
            min: 0,
            max: 32,
            stepsize: 1,
            resource_type: :object,
            allocate_chain: 'Ip::Allocate',
            free_chain: 'Ip::Free'
        )
      end
    end
  end
end
