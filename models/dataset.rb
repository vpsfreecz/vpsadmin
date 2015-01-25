class Dataset < ActiveRecord::Base
  belongs_to :user
  has_many :dataset_in_pools
  has_many :snapshots

  has_ancestry cache_depth: true

  validates :name, format: {
      with: /\A[a-zA-Z0-9][a-zA-Z0-9_\-:\.]{0,254}\z/,
      message: "'%{value}' is not a valid dataset name"
  }
  validate :check_name

  before_save :cache_full_name

  include Confirmable
  include VpsAdmin::API::Maintainable::Check

  def self.create_new(name, parent_ds, automount)
    parts = name.split('/')

    if parts.empty?
      fail 'FIXME: invalid path'
    end

    # Parent dataset is specified, use it
    if parent_ds
      # top_dip is not the root of the tree (though it may be), but the pool role
      # is the same anyway.
      top_dip = parent_ds.primary_dataset_in_pool!

      _, path = top_dip.dataset.send(:create_path, top_dip, parts)
      last = parent_ds

    # Parent dataset is not set, try to locate it using label
    else
      top_dip = ::DatasetInPool.includes(:dataset).joins(:dataset)
                    .find_by(label: parts.first,
                             datasets: {user_id: User.current.id})

      if !top_dip
        raise VpsAdmin::API::Exceptions::DatasetLabelDoesNotExist, parts.first

      # TODO: access control should be in controller
      elsif User.current.role != :admin && top_dip.dataset.user_id != User.current.id
        raise VpsAdmin::API::Exceptions::AccessDenied
      end

      last, path = top_dip.dataset.send(:create_path, top_dip, parts[1..-1])
    end

    # VPS subdatasets are more complicated and need special handling
    if top_dip.pool.role == 'hypervisor'
      vps = Vps.find_by!(dataset_in_pool: top_dip.dataset.root.primary_dataset_in_pool!)
      maintenance_check!(vps)
    end

    TransactionChains::Dataset::Create.fire(
        (last && last.primary_dataset_in_pool!) || top_dip,
        path,
        automount
    )
  end

  def destroy
    dip = primary_dataset_in_pool!

    if dip.pool.role == 'hypervisor'
      vps = Vps.find_by!(dataset_in_pool: dip.dataset.root.primary_dataset_in_pool!)
      maintenance_check!(vps)
    end

    TransactionChains::DatasetInPool::Destroy.fire(dip, true)
  end

  def check_name
    if name.present?
      if name =~ /\.\./
        errors.add(:mountpoint, "'..' not allowed in dataset name")
      end
    end
  end

  def resolve_full_name
    if parent_id
      "#{parent.resolve_full_name}/#{name}"
    else
      name
    end
  end

  # Returns DatasetInPool of +self+ on pools with +hypervisor+
  # or +primary+ role.
  def primary_dataset_in_pool!
    dataset_in_pools.joins(:pool).where.not(pools: {role: Pool.roles[:backup]}).take!
  end

  def snapshot
    dip = primary_dataset_in_pool!

    if dip.pool.role == 'hypervisor'
      vps = Vps.find_by!(dataset_in_pool: dip.dataset.root.primary_dataset_in_pool!)
      maintenance_check!(vps)
    end

    dip.snapshot
  end

  def rollback_snapshot(s)
    dip = primary_dataset_in_pool!

    if dip.pool.role == 'hypervisor'
      vps = Vps.find_by!(dataset_in_pool: dip.dataset.root.primary_dataset_in_pool!)
      maintenance_check!(vps)

      vps.restore(s)

    else
      fail 'not implemented'
    end
  end

  protected
  def cache_full_name
    self.full_name = resolve_full_name
  end

  # Returns a list of two objects.
  # - +[0]+ is the last dataset that exists
  # - +[1]+ is a list of newly created datasets
  def create_path(parent_dip, parts)
    tmp = parent_dip.dataset
    ret = []
    last = nil

    if parts.empty?
      ds = Dataset.new
      ds.valid?
      raise ::ActiveRecord::RecordInvalid, ds
    end

    parts.each do |part|
      # As long as tmp is not nil, we're iterating over existing datasets.
      if tmp
        ds = tmp.children.find_by(name: part)

        if ds
          # Add the dataset to ret if it is NOT present on pool with hypervisor role.
          # It means that the dataset was destroyed and is presumably only in backup.
          if ds.dataset_in_pools.where(pool_id: parent_dip.pool_id).pluck(:id).empty?
            ret << ds
          else
            last = ds
          end

          tmp = ds

        else
          ret << dataset_create_append_new(part, tmp)
          tmp = nil
        end

      else
        ret << dataset_create_append_new(part, nil)
      end
    end

    if ret.empty?
      raise VpsAdmin::API::Exceptions::DatasetAlreadyExists.new(tmp, parts.join('/'))
    end

    [last, ret]
  end

  # Return new Dataset object. Object is validated and exception
  # may be raised.
  def dataset_create_append_new(part, parent)
    new_ds = ::Dataset.new(
        name: part,
        user: User.current,
        user_editable: true,
        user_create: true,
        user_destroy: true,
        confirmed: ::Dataset.confirmed(:confirm_create)
    )

    new_ds.parent = parent if parent

    raise ::ActiveRecord::RecordInvalid, new_ds unless new_ds.valid?

    new_ds
  end
end
