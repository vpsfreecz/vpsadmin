class AddStorage < ActiveRecord::Migration
  class Node < ActiveRecord::Base
    self.table_name = 'servers'
    self.primary_key = 'server_id'
  end

  class Vps < ActiveRecord::Base
    self.table_name = 'vps'
    self.primary_key = 'vps_id'

    belongs_to :dataset_in_pool
  end

  class Pool < ActiveRecord::Base
  end

  class Dataset < ActiveRecord::Base
    has_ancestry cache_depth: true
  end

  class DatasetInPool < ActiveRecord::Base
    has_many :vpses
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

      t.integer    :quota,          null: false, default: 0
      t.integer    :used,           null: false, default: 0
      t.integer    :avail,          null: false, default: 0
      t.string     :share_options,  null: false, limit: 500
      t.boolean    :compression,    null: false
    end

    change_column :pools, :quota, 'bigint unsigned'
    change_column :pools, :used, 'bigint unsigned'
    change_column :pools, :avail, 'bigint unsigned'

    # Represents a dataset, datasets may be nested.
    # Notice that there is no connection to a pool dataset is in,
    # that particular connection is made in dataset_in_pools.
    create_table :datasets do |t|
      t.string     :name,           null: false, limit: 500
      t.references :user,           null: true
      t.boolean    :user_editable,  null: false
      t.boolean    :user_create,    null: false

      t.integer    :quota,          null: false, default: 0

      # if the following attributes are not set, they are inherited
      # from parent dataset or pool.
      t.string     :share_options,  null: true,  limit: 500
      t.boolean    :compression,    null: true

      t.string     :ancestry,       null: true,  limit: 255
      t.integer    :ancestry_depth, null: false, default: 0

      t.boolean    :confirmed,      null: false, default: 0
    end

    change_column :datasets, :quota, 'bigint unsigned'
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

      # if the following attributes are not set, they are inherited
      # from dataset.
      t.string     :mountpoint,     null: true,  limit: 500
      t.string     :share_options,  null: true,  limit: 500
      t.boolean    :compression,    null: true

      # dataset is marked as confirmed when vpsadmind creates it
      t.integer    :confirmed,      null: false, default: 0
    end

    change_column :dataset_in_pools, :used, 'bigint unsigned'
    change_column :dataset_in_pools, :avail, 'bigint unsigned'
    add_index :dataset_in_pools, [:dataset_id, :pool_id], unique: true

    create_table :snapshots do |t|
      t.string     :name,           null: false
      t.references :dataset,        null: false

      # snapshot is marked as confirmed when vpsadmind creates it
      t.integer    :confirmed,      null: false, default: 0

      t.timestamps
    end

    # A snapshot can exist on multiple nodes, it is in fact
    # necessary for their transfers to work.
    create_table :snapshot_in_pools do |t|
      t.references :snapshot,       null: false
      t.references :dataset_in_pool, null: false

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
      t.integer    :reference_count,  null: false, default: 0
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
      t.references :dataset_in_pool, null: true

      # ro, rw
      t.string     :mode,           null: false, limit: 2

      # Commands executed in the VPS context
      t.string     :cmd_premount,   null: false, limit: 500
      t.string     :cmd_postmount,  null: false, limit: 500
      t.string     :cmd_preumount,  null: false, limit: 500
      t.string     :cmd_postumount, null: false, limit: 500
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
      t.integer    :dependency_id,  null: true # action will depend on previous action
      t.integer    :last_transaction_id, null: true

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

    group_snapshots_per_pool = {}

    # Create pools for all hypervisors
    Node.where(server_type: 'node').each do |node|
      pool = Pool.create({
          node_id: node.id,
          label: "#{node.server_name}: vz/private",
          filesystem: 'vz/private',
          role: 0, # :hypervisor
          share_options: '',
          compression: true
      })

      group_snapshots_per_pool[ pool.id ] = DatasetAction.create(
          pool_id: pool.id,
          action: 4 # group_snapshot
      )

      # Create a dataset for every VPS
      Vps.where(vps_server: node.id).each do |vps|
        ds = Dataset.create(
            name: vps.id,
            user_id: vps.m_id,
            user_editable: false,
            user_create: true,
            quota: 0,
            share_options: '',
            compression: false
        )

        ds_in_pool = DatasetInPool.create(
            dataset_id: ds.id,
            pool_id: pool.id,
            label: vps.id,
            min_snapshots: 1,
            max_snapshots: 1,
            snapshot_max_age: 1*24*60*60,
            confirmed: 1
        )

        vps.update(dataset_in_pool_id: ds_in_pool.id)

        # Add to group snapshots
        group_snapshots_per_pool[pool.id].group_snapshots << GroupSnapshot.new(dataset_in_pool_id: ds_in_pool.id)
      end
    end

    pool_mapping = {}

    # Add already existing pools (NAS+backups)
    StorageRoot.all.each do |root|
      ex = StorageExport.find_by(root_id: root.id)

      r = Pool.create(
          node_id: root.node_id,
          label: root.label,
          filesystem: root.root_dataset,
          role: ex && ex.data_type == 'backup' ? 2 : 1,
          share_options: root.share_options,
          compression: true
      )

      group_snapshots_per_pool[ r.id ] = DatasetAction.create(
          pool_id: r.id,
          action: 4 # group_snapshot
      )

      pool_mapping[root.id] = r.id
    end

    # Create repeatable tasks for all group snapshots
    group_snapshots_per_pool.each do |k, v|
      RepeatableTask.create(
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
    StorageExport.where(data_type: 'data', default: 'no').each do |export|
      ds_in_pool = nil
      last_ds = nil
      ds = nil
      index = 0
      parts = export.dataset.split('/')

      parts.each do |name|
        # FIXME
        # This is wrong. The dataset must be found in appropriate pool,
        # it cannot be just any random dataset with the same name.
        ds = (ds ? Dataset.children_of(ds) : Dataset.roots).find_by(name: name)

        if ds
          last_ds = ds
          index += 1
        else
          break
        end
      end

      parts[index..-1].each do |name|
        ds = Dataset.create(
            name: name,
            parent: ds,
            user_id: export.member_id,
            user_editable: ds ? export.user_editable : false,
            user_create: export.user_editable,
            quota: export.quota,
            confirmed: 1
        )

        ds_in_pool = DatasetInPool.create(
          dataset_id: ds.id,
          pool_id: pool_mapping[ export.root_id ],
          label: ds ? nil : 'nas',
          used: export.used,
          avail: export.avail,
          confirmed: 1
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

      ds_in_pool = DatasetInPool.create(
          dataset_id: vps.dataset_in_pool.dataset_id,
          pool_id: pool_id,
          confirmed: 1
      )

      # Mounts
      if ex
        ex.vps_mounts.all.each do |m|
          migrate_mount(m, ds_in_pool.id)
        end

      # FIXME: create mount even if none exist?
      end

      # Transfer snapshots at 01:30 every day
      backup = DatasetAction.create(
          src_dataset_in_pool_id: vps.dataset_in_pool_id,
          dst_dataset_in_pool_id: ds_in_pool.id,
          action: 3 # :backup
      )

      RepeatableTask.create(
          class_name: backup.class.to_s.demodulize,
          table_name: backup.class.table_name,
          row_id: backup.id,
          minute: '30',
          hour: '01',
          day_of_month: '*',
          month: '*',
          day_of_week: '*'
      )
    end
    # FIXME: update vps_ip.vps_id = null where = 0
    # FIXME: put this in another, irreversable migration
    # drop_table :storage_root
    # drop_table :storage_export
    # drop_table :vps_mount
    # remove_column :vps, :vps_backup_enabled # rly?
    # remove_column :vps, :vps_backup_export
    # remove_column :vps, :vps_backup_exclude
  end

  def down
    drop_table :pools
    drop_table :datasets
    drop_table :dataset_in_pools
    drop_table :snapshots
    drop_table :snapshot_in_pools
    drop_table :dataset_trees
    drop_table :branches
    drop_table :snapshot_in_pool_in_branches
    drop_table :mounts
    drop_table :mirrors
    drop_table :repeatable_tasks
    drop_table :dataset_actions
    drop_table :group_snapshots

    remove_column :vps, :dataset_in_pool_id
  end

  private
  def migrate_mount(m, ds_in_pool_id)
    Mount.create(
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
