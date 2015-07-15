class AddStorage < ActiveRecord::Migration
  class Environment < ActiveRecord::Base
  end

  class Location < ActiveRecord::Base
  end

  class Node < ActiveRecord::Base
    self.table_name = 'servers'
    self.primary_key = 'server_id'

    belongs_to :location, :foreign_key => :server_location
  end

  class Vps < ActiveRecord::Base
    self.table_name = 'vps'
    self.primary_key = 'vps_id'

    belongs_to :dataset_in_pool
    belongs_to :node, :foreign_key => :vps_server
    has_many :vps_mounts
  end

  class Pool < ActiveRecord::Base
  end

  class Dataset < ActiveRecord::Base
    has_many :dataset_in_pools
    has_many :dataset_properties

    has_ancestry cache_depth: true

    before_save :cache_full_name

    def resolve_full_name
      if parent_id
        "#{parent.resolve_full_name}/#{name}"
      else
        name
      end
    end

    protected
    def cache_full_name
      self.full_name = resolve_full_name
    end
  end

  class DatasetInPool < ActiveRecord::Base
    has_many :vpses
    belongs_to :dataset
    has_many :dataset_properties
  end

  class DatasetProperty < ActiveRecord::Base
    belongs_to :pool
    belongs_to :dataset_in_pool
    belongs_to :dataset

    has_ancestry cache_depth: true

    serialize :value

    def self.inherit_properties!(dataset_in_pool, parents = {}, values = {})
      ret = {}
      root = false

      if parents.empty?
        self.joins(:dataset_in_pool).where(
            dataset: dataset_in_pool.dataset.parent,
            dataset_in_pools: {pool_id: dataset_in_pool.pool_id}
        ).each do |p|
          parents[p.name.to_sym] = p
        end
      end

      if parents.empty?
        root = true
      end

      VpsAdmin::API::DatasetProperties::Registrator.properties.each do |name, p|
        property = self.new(
            dataset_in_pool: dataset_in_pool,
            dataset: dataset_in_pool.dataset,
            parent: parents[name],
            name: name,
            confirmed: 1
        )

        if values[name]
          property.value = values[name]
          property.inherited = false
        else
          property.value = root ? (p.meta[:default]) : (p.inheritable? ? parents[name].value : p.meta[:default])
          property.inherited = root ? false : p.inheritable?
        end

        property.save!
        ret[name] = property
      end

      ret
    end
  end

  class Mount < ActiveRecord::Base
  end

  class StorageRoot < ActiveRecord::Base
    self.table_name = 'storage_root'
  end

  class StorageExport < ActiveRecord::Base
    self.table_name = 'storage_export'

    has_many :vps_mounts
  end

  class VpsMount < ActiveRecord::Base
    self.table_name = 'vps_mount'

    belongs_to :storage_export
  end

  class DatasetPlan < ActiveRecord::Base

  end

  class EnvironmentDatasetPlan < ActiveRecord::Base
  end

  class DatasetInPoolPlan < ActiveRecord::Base

  end

  class RepeatableTask < ActiveRecord::Base

  end

  class DatasetAction < ActiveRecord::Base
    has_many :group_snapshots
  end

  class GroupSnapshot < ActiveRecord::Base

  end

  def up
    # A storage root, a prefix for all datasets in a pool.
    # There may be multiple pools on every node.
    create_table :pools do |t|
      t.references :node,           null: false
      t.string     :label,          null: false, limit: 500
      t.string     :filesystem,     null: false, limit: 500

      # Enum role
      # hypervisor: the pool contains datasets with VPSes
      # primary: the origin of the datasets in the pool is here, general purpose (for NAS)
      # backup: datasets in the pool are backups, branching is used
      t.integer    :role,           null: false

      # When set, refquotas in all descendant datasets are checked
      # if they fit into the parent quota every time they're changed.
      t.boolean    :refquota_check, null: false, default: false
    end

    # Represents a dataset, datasets may be nested.
    # Notice that there is no connection to a pool dataset is in,
    # that particular connection is made in dataset_in_pools.
    create_table :datasets do |t|
      t.string     :name,           null: false, limit: 255
      t.string     :full_name,      null: false, limit: 1000
      t.references :user,           null: true
      t.boolean    :user_editable,  null: false
      t.boolean    :user_create,    null: false
      t.boolean    :user_destroy,   null: false

      t.string     :ancestry,       null: true,  limit: 255
      t.integer    :ancestry_depth, null: false, default: 0

      t.datetime   :expiration,     null: true

      t.boolean    :confirmed,      null: false, default: 0
    end

    add_index :datasets, :ancestry

    # Dataset may exist on multiple nodes in different roles
    create_table :dataset_in_pools do |t|
      t.references :dataset,        null: false
      t.references :pool,           null: false

      # An optional label, may serve as a shortcut to this dataset.
      t.string     :label,          null: true,  limit: 100

      t.integer    :used,           null: false, default: 0
      t.integer    :avail,          null: false, default: 0

      t.integer    :min_snapshots,  null: false, default: 14
      t.integer    :max_snapshots,  null: false, default: 20
      t.integer    :snapshot_max_age, null: false, default: 14 * 24 * 60 * 60 # seconds

      t.string     :mountpoint,     null: true,  limit: 500

      # dataset is marked as confirmed when vpsadmind creates it
      t.integer    :confirmed,      null: false, default: 0
    end

    add_index :dataset_in_pools, [:dataset_id, :pool_id], unique: true

    create_table :snapshots do |t|
      t.string     :name,           null: false
      t.references :dataset,        null: false

      # snapshot is marked as confirmed when vpsadmind creates it
      t.integer    :confirmed,      null: false, default: 0

      t.timestamps
    end

    create_table :dataset_properties do |t|
      t.references :pool,            null: true
      t.references :dataset,         null: true
      t.references :dataset_in_pool, null: true

      t.string     :ancestry,        null: true,  limit: 255
      t.integer    :ancestry_depth,  null: false, default: 0

      t.string     :name,            null: false, limit: 30
      t.string     :value,           null: true,  limit: 255
      t.boolean    :inherited,       null: false, default: true
      t.integer    :confirmed,       null: false, default: 0

      t.timestamps
    end

    # A snapshot can exist on multiple nodes, it is in fact
    # necessary for their transfers to work.
    create_table :snapshot_in_pools do |t|
      t.references :snapshot,       null: false
      t.references :dataset_in_pool, null: false
      t.integer    :reference_count,  null: false, default: 0
      t.references :mount,          null: true

      # snapshot is marked as confirmed when vpsadmind creates it
      t.integer    :confirmed,      null: false, default: 0
    end

    add_index :snapshot_in_pools, [:snapshot_id, :dataset_in_pool_id], unique: true

    create_table :dataset_trees do |t|
      t.references :dataset_in_pool, null: false
      t.integer    :index,           null: false, default: 0
      t.boolean    :head,            null: false, default: false
      t.integer    :confirmed,       null: false, default: 0
      t.timestamps
    end

    create_table :branches do |t|
      t.references :dataset_tree,    null: false
      t.string     :name,            null: false
      t.integer    :index,           null: false, default: 0
      t.boolean    :head,            null: false, default: false
      t.integer    :confirmed,       null: false, default: 0
      t.timestamps
    end

    create_table :snapshot_in_pool_in_branches do |t|
      t.references :snapshot_in_pool, null: false
      # a zfs-parent snapshot, dependency created by zfs clone & promote
      t.integer    :snapshot_in_pool_in_branch_id, null: true
      t.references :branch,           null: false
      t.integer    :confirmed,        null: false, default: 0
    end

    add_index :snapshot_in_pool_in_branches, [:snapshot_in_pool_id, :branch_id],
              unique: true, name: 'unique_snapshot_in_pool_in_branches'

    create_table :mounts do |t|
      t.references :vps,            null: false
      t.string     :src,            null: true,  limit: 500
      t.string     :dst,            null: false, limit: 500
      t.string     :mount_opts,     null: false, limit: 255
      t.string     :umount_opts,    null: false, limit: 255
      t.string     :mount_type,     null: false, limit: 10
      t.boolean    :user_editable,  null: false, default: true

      t.references :dataset_in_pool, null: true
      t.references :snapshot_in_pool, null: true

      # ro, rw
      t.string     :mode,           null: false, limit: 2

      # Commands executed in the VPS context
      t.string     :cmd_premount,   null: true,  limit: 500
      t.string     :cmd_postmount,  null: true,  limit: 500
      t.string     :cmd_preumount,  null: true,  limit: 500
      t.string     :cmd_postumount, null: true,  limit: 500

      t.integer    :confirmed,      null: false, default: 0
    end

    # Setup mirrors, will not be implemented yet though.
    create_table :mirrors do |t|
      t.integer    :src_pool_id,    null: true
      t.integer    :dst_pool_id,    null: true
      t.integer    :src_dataset_in_pool_id, null: true
      t.integer    :dst_dataset_in_pool_id, null: true
      t.boolean    :recursive,      null: false, default: false
      t.integer    :interval,       null: false, default: 60 # in seconds
    end

    create_table :dataset_plans do |t|
      t.string     :name,            null: false
    end

    create_table :environment_dataset_plans do |t|
      t.references :environment,     null: false
      t.references :dataset_plan,    null: false
      t.boolean    :user_add,        null: false
      t.boolean    :user_remove,     null: false
    end

    create_table :dataset_in_pool_plans do |t|
      t.references :environment_dataset_plan,    null: false
      t.references :dataset_in_pool, null: false
    end

    add_index :dataset_in_pool_plans, [:environment_dataset_plan_id, :dataset_in_pool_id],
              unique: true, name: :dataset_in_pool_plans_unique

    create_table :repeatable_tasks do |t|
      t.string     :label,          null: true,  limit: 100
      t.string     :class_name,     null: false, limit: 255
      t.string     :table_name,     null: false, limit: 255
      t.integer    :row_id,         null: false

      # Scheduling
      t.string    :minute,          null: false, limit: 255
      t.string    :hour,            null: false, limit: 255
      t.string    :day_of_month,    null: false, limit: 255
      t.string    :month,           null: false, limit: 255
      t.string    :day_of_week,     null: false, limit: 255
    end

    # Schedule dataset actions
    # Possible uses:
    # - daily backups - schedule snapshot and transfer afterwards
    # - snapshot every hour, transfer once a day
    # - snapshot of NAS datasets, backups of NAS datasets
    # - regular rollback (regularly reset a VPS to an initial state
    #   or whatever)
    create_table :dataset_actions do |t|
      t.references :pool,           null: true
      t.integer    :src_dataset_in_pool_id, null: true
      t.integer    :dst_dataset_in_pool_id, null: true
      t.references :snapshot,       null: true # for rollback
      t.boolean    :recursive,      null: false, default: false
      t.references :dataset_plan,   null: true
      t.references :dataset_in_pool_plan, null: true

      # Enum action
      # snapshot: create a snapshot
      # transfer: transfer snapshots from src to dst
      # rollback: rollback to snapshot
      # backup
      # group_snapshot
      #           (may have to be fetched from the backup of src snapshot)
      t.integer    :action,         null: false
    end

    create_table :group_snapshots do |t|
      t.references :dataset_action
      t.references :dataset_in_pool
    end

    add_column :vps, :dataset_in_pool_id, :integer, null: true

    # Setup environments
    Environment.all.delete_all
    production_env = Environment.create!(
        label: 'Production',
        domain: 'vpsfree.cz'
    )

    # Create dataset plans
    backup_plan = DatasetPlan.create!(name: :daily_backup)
    env_backup_plan = EnvironmentDatasetPlan.create!(
        dataset_plan_id: backup_plan.id,
        environment_id: production_env.id,
        user_add: true,
        user_remove: true
    )

    group_snapshots_per_pool = {}

    # Create pools for all hypervisors
    Node.where(server_type: 'node').each do |node|
      pool = Pool.create!({
          node_id: node.id,
          label: "#{node.server_name}: vz/private",
          filesystem: 'vz/private',
          role: 0, # :hypervisor
          refquota_check: true
      })

      pool_properties = {}

      VpsAdmin::API::DatasetProperties::Registrator.properties.each do |k, v|
        pool_properties[k] = DatasetProperty.create!(
            pool: pool,
            name: k,
            value: v.meta[:default],
            inherited: false
        )
      end

      # FIXME: cannot call here, necessary DB changes for chains
      # to work are in later migrations...
      # TransactionChains::Pool::Create.fire(pool)

      group_snapshots_per_pool[ pool.id ] = DatasetAction.create!(
          pool_id: pool.id,
          action: 4, # group_snapshot
          dataset_plan_id: backup_plan.id
      )

      # Create a dataset for every VPS
      Vps.where(vps_server: node.id).each do |vps|
        ds = Dataset.create!(
            name: vps.id,
            user_id: vps.m_id,
            user_editable: false,
            user_create: true,
            user_destroy: false
        )

        ds_in_pool = DatasetInPool.create!(
            dataset_id: ds.id,
            pool_id: pool.id,
            label: "vps#{vps.id}",
            min_snapshots: 1,
            max_snapshots: 1,
            snapshot_max_age: 1*24*60*60,
            confirmed: 1
        )

        VpsAdmin::API::DatasetProperties::Registrator.properties.each do |k, v|
          DatasetProperty.create!(
              dataset: ds,
              dataset_in_pool: ds_in_pool,
              name: k,
              value: k == :refquota ? 60*1024 : v.meta[:default],
              inherited: v.inheritable?,
              parent: pool_properties[k]
          )
        end

        vps.update!(dataset_in_pool_id: ds_in_pool.id)

        # Add to group snapshots
        group_snapshots_per_pool[pool.id].group_snapshots << GroupSnapshot.new(dataset_in_pool_id: ds_in_pool.id)
      end
    end

    pool_mapping = {}
    nas_pool_properties = {}
    dataset_mapping = {}

    # Add already existing pools (NAS+backups)
    StorageRoot.all.each do |root|
      ex = StorageExport.find_by(root_id: root.id)

      r = Pool.create!(
          node_id: root.node_id,
          label: root.label,
          filesystem: root.root_dataset,
          role: ex && ex.data_type == 'backup' ? 2 : 1
      )

      nas_pool_properties[r.id] = {}

      VpsAdmin::API::DatasetProperties::Registrator.properties.each do |k, v|
        nas_pool_properties[r.id][k] = DatasetProperty.create!(
            pool: r,
            name: k,
            value: v.meta[:default],
            inherited: false
        )
      end

      # FIXME
      # TransactionChains::Pool::Create.fire(r)

      pool_mapping[root.id] = r.id
    end

    # Create repeatable tasks for all group snapshots
    group_snapshots_per_pool.each do |k, v|
      RepeatableTask.create!(
          label: "group_snapshot of pool #{k}",
          class_name: v.class.to_s.demodulize,
          table_name: v.class.table_name,
          row_id: v.id,
          minute: '00',
          hour: '01',
          day_of_month: '*',
          month: '*',
          day_of_week: '*'
      )
    end

    # Add already existing datasets (NAS, exports)
    StorageExport.where(
        data_type: 'data',
        default: 'no'
    ).order('dataset ASC').each do |export|
      ds_in_pool = nil
      last_ds = nil
      ds = nil
      index = 0
      parts = export.dataset.split('/')
      parent_properties = {}

      parts.each do |name|
        # Find all datasets with matching name, then see if any of them are
        # on the correct pool. 
        q = (ds ? Dataset.children_of(ds) : Dataset.roots).where(
            name: name,
            user_id: export.member_id
        )
        ds = nil

        break if q.empty?
        
        q.each do |dataset|
          if dataset.dataset_in_pools.exists?(
                pool_id: pool_mapping[ export.root_id ]
             )
            last_ds = dataset
            index += 1
            break
          end
        end

        break unless ds
      end

      parts[index..-1].each do |name|
        new_ds = Dataset.create!(
            name: name,
            parent: last_ds,
            user_id: export.member_id,
            user_editable: last_ds ? export.user_editable : false,
            user_create: export.user_editable,
            user_destroy: false,
            confirmed: 1
        )

        ds_in_pool = DatasetInPool.create!(
          dataset_id: new_ds.id,
          pool_id: pool_mapping[ export.root_id ],
          label: new_ds ? nil : 'nas',
          confirmed: 1
        )

        dataset_mapping[ export.id ] = ds_in_pool

        parent_properties = DatasetProperty.inherit_properties!(
            ds_in_pool,
            parent_properties,
            export.quota > 0 ? {quota: export.quota / 1024 / 1024} : {}
        )
      end

      # Mounts of this export
      # export.vps_mounts.all.each do |m|
      #   migrate_mount(m, ds_in_pool.id)
      # end
    end

    # Create backup datasets for VPS
    Vps.all.each do |vps|
      ex = StorageExport.find_by(id: vps.vps_backup_export)

      pool_id = nil

      if ex
        pool_id =  pool_mapping[ ex.root_id ]
      else
        p = Pool.find_by(role: 2)

        next unless p

        pool_id = p.id
      end

      ds_in_pool = DatasetInPool.create!(
          dataset_id: vps.dataset_in_pool.dataset_id,
          pool_id: pool_id,
          confirmed: 1
      )

      dataset_mapping[ ex.id ] = ds_in_pool if ex

      # Mounts
      vps.vps_mounts.all.each do |m|
        dst = dataset_mapping[ m.storage_export_id ]

        if dst
          migrate_mount(m, dst.id)
        else
          warn "unable to migrate mount #{m.id}: storage export does not exist"
          warn ex ? "ex is set" : "ex is not set"
        end
      end

      dip_plan = DatasetInPoolPlan.create!(
          environment_dataset_plan_id: env_backup_plan.id,
          dataset_in_pool_id: vps.dataset_in_pool_id
      )

      # Transfer snapshots at 01:30 every day
      backup = DatasetAction.create!(
          src_dataset_in_pool_id: vps.dataset_in_pool_id,
          dst_dataset_in_pool_id: ds_in_pool.id,
          action: 3, # :backup
          dataset_in_pool_plan_id: dip_plan.id
      )

      RepeatableTask.create!(
          class_name: backup.class.to_s.demodulize,
          table_name: backup.class.table_name,
          row_id: backup.id,
          minute: '05',
          hour: '01',
          day_of_month: '*',
          month: '*',
          day_of_week: '*'
      )
    end
    
    drop_table :storage_root
    drop_table :storage_export
    drop_table :vps_mount
    remove_column :vps, :vps_backup_enabled
    remove_column :vps, :vps_backup_export
    remove_column :vps, :vps_backup_exclude
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private
  def migrate_mount(m, ds_in_pool_id)
    Mount.create!(
        vps_id: m.vps_id,
        src: m.src,
        dst: m.dst,
        mount_opts: m.mount_opts,
        umount_opts: m.umount_opts,
        mount_type: m.mount_type.empty? ? 'nfs' : m.mount_type,
        dataset_in_pool_id: ds_in_pool_id,
        mode: m.mode,
        cmd_premount: m.cmd_premount,
        cmd_postmount: m.cmd_postmount,
        cmd_preumount: m.cmd_preumount,
        cmd_postumount: m.cmd_postumount
    )
  end
end

# Create subdataset in a VPS, 101 is a dataset label
# $ vpsfreectl dataset create -- --name 101/var/lib/mysql
# > 1568

# Create a subdataset in NAS, nas is a label
# $ vpsfreectl dataset create -- --name nas/aintthatnice
# $ > 1569
# $ vpsfreectl mount create -- --dataset 1568 --vps 101 --mountpoint /var/lib/mysql

# $ vpsfreectl dataset task 1568 -- --backup yes
