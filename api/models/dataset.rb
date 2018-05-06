class Dataset < ActiveRecord::Base
  belongs_to :user
  has_many :dataset_in_pools
  has_many :snapshots
  has_many :dataset_properties

  has_ancestry cache_depth: true

  before_save :cache_full_name

  include Confirmable
  include Lockable
  include VpsAdmin::API::Maintainable::Check
  include VpsAdmin::API::DatasetProperties::Model

  include VpsAdmin::API::Lifetimes::Model
  set_object_states states: %i(active deleted),
                    deleted: {
                      enter: TransactionChains::Dataset::Destroy
                    }

  validates :name, format: {
    with: /\A[a-zA-Z0-9][a-zA-Z0-9_\-:\.]{0,254}\z/,
    message: "'%{value}' is not a valid dataset name"
  }, exclusion: {
    in: %w(private vpsadmin),
    message: "'%{value}' is a reserved name"
  }
  validate :check_name

  def self.create_new(name, parent_ds, automount, properties)
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

    parent_dip = (last && last.primary_dataset_in_pool!) || top_dip
    top_dip.dataset.send(
      :check_refquota,
      top_dip,
      path,
      properties[:refquota]
    )

    # VPS subdatasets are more complicated and need special handling
    if top_dip.pool.role == 'hypervisor'
      vps = Vps.find_by!(dataset_in_pool: top_dip.dataset.root.primary_dataset_in_pool!)
      maintenance_check!(vps)
    end

    maintenance_check!(top_dip.pool)

    TransactionChains::Dataset::Create.fire(
      parent_dip.pool,
      parent_dip,
      path,
      automount,
      properties
    )
  end

  def destroy
    dip = primary_dataset_in_pool!

    if dip.pool.role == 'hypervisor'
      vps = Vps.find_by!(dataset_in_pool: dip.dataset.root.primary_dataset_in_pool!)
      maintenance_check!(vps)
    end

    TransactionChains::DatasetInPool::Destroy.fire(dip, {recursive: true})
  end

  def check_name
    if name.present?
      if name =~ /\.\./
        errors.add(:mountpoint, "'..' not allowed in dataset name")
      end

      %w(branch- tree.).each do |prefix|
        if name.start_with?(prefix)
          errors.add(:name, "cannot start with prefix '#{prefix}'")
          break
        end
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

  def environment
    dataset_in_pools.each do |dip|
      return dip.pool.node.location.environment if dip.pool.role != 'backup'
    end

    nil
  end

  # Returns DatasetInPool of +self+ on pools with +hypervisor+
  # or +primary+ role.
  def primary_dataset_in_pool!
    dataset_in_pools.joins(:pool).where.not(pools: {role: Pool.roles[:backup]}).take!
  end

  # Return the maximum number of snapshots of all dataset in pools
  def max_snapshots
    dataset_in_pools.maximum(:max_snapshots)
  end

  def update_properties(properties, opts)
    dip = primary_dataset_in_pool!

    check_refquota(
      dip,
      [],
      properties[:refquota]
    )

    TransactionChains::Dataset::Set.fire(
      dip,
      properties,
      opts
    )
  end

  def inherit_properties(properties)
    TransactionChains::Dataset::Inherit.fire(self.primary_dataset_in_pool!, properties)
  end

  # @param opts [Hash] options
  # @option opts [String] label user-friendly snapshot label
  def snapshot(opts = {})
    dip = primary_dataset_in_pool!

    if dip.pool.role == 'hypervisor'
      vps = Vps.find_by!(dataset_in_pool: dip.dataset.root.primary_dataset_in_pool!)
      maintenance_check!(vps)
    end

    dip.snapshot(opts)
  end

  def rollback_snapshot(s)
    dip = primary_dataset_in_pool!

    if dip.pool.role == 'hypervisor'
      vps = Vps.find_by!(dataset_in_pool: dip.dataset.root.primary_dataset_in_pool!)
      maintenance_check!(vps)

      vps.restore(s)

    else
      TransactionChains::Dataset::Rollback.fire(dip, s)
    end
  end

  # Since property `quota` can be `none`, i.e. `0`, this method returns
  # quota from the closest parent that has it set.
  def effective_quota
    return quota if quota != 0 || root?
    parent.effective_quota
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

  def check_refquota(dip, path, refquota)
    # Refquota enforcement
    if dip.pool.refquota_check
      if refquota.nil?
        raise VpsAdmin::API::Exceptions::PropertyInvalid, 'refquota must be set'
      end

      i = 0
      path.each do |p|
        i += 1 if p.new_record?

        if i > 1
          raise VpsAdmin::API::Exceptions::DatasetNestingForbidden, 'Cannot create more than one dataset at a time'
        end
      end
    end
  end
end
