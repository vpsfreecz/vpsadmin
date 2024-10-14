require 'vpsadmin/api/operations/base'
require 'vpsadmin/api/operations/dataset/utils'

module VpsAdmin::API
  class Operations::Dataset::Create < Operations::Base
    include VpsAdmin::API::Maintainable::Check
    include Operations::Dataset::Utils

    # @param name [String]
    # @param parent_ds [::Dataset]
    # @param opts [Hash]
    # @option opts [Boolean] :automount
    # @option opts [Hash] :properties
    # @return [Array<TransactionChain, Dataset>]
    def run(name, parent_ds, **opts)
      opts[:properties] ||= {}
      parts = name.split('/')

      raise 'FIXME: invalid path' if parts.empty?

      # Parent dataset is specified, use it
      if parent_ds
        # top_dip is not the root of the tree (though it may be), but the pool role
        # is the same anyway.
        top_dip = parent_ds.primary_dataset_in_pool!

        _, path = create_path(top_dip, parts)
        last = parent_ds

      # Parent dataset is not set, try to locate it using label
      else
        top_dip = ::DatasetInPool.includes(:dataset).joins(:dataset)
                                 .find_by(label: parts.first,
                                          datasets: { user_id: ::User.current.id })

        if !top_dip
          raise VpsAdmin::API::Exceptions::DatasetLabelDoesNotExist, parts.first

        # TODO: access control should be in controller
        elsif ::User.current.role != :admin && top_dip.dataset.user_id != ::User.current.id
          raise VpsAdmin::API::Exceptions::AccessDenied
        end

        last, path = create_path(top_dip, parts[1..])
      end

      parent_dip = (last && last.primary_dataset_in_pool!) || top_dip
      check_refquota(
        top_dip,
        path,
        opts[:properties][:refquota]
      )

      # VPS subdatasets are more complicated and need special handling
      if top_dip.pool.role == 'hypervisor'
        vps = Vps.find_by!(dataset_in_pool: top_dip.dataset.root.primary_dataset_in_pool!)
        maintenance_check!(vps)

        opts[:userns_map] = vps.user_namespace_map
      end

      maintenance_check!(top_dip.pool)

      chain, dips = TransactionChains::Dataset::Create.fire(
        parent_dip.pool,
        parent_dip,
        path,
        opts
      )
      [chain, dips.last.dataset]
    end

    protected

    # Returns a list of two objects.
    # - `[0]` is the last dataset that exists
    # - `[1]` is a list of newly created datasets
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

      raise VpsAdmin::API::Exceptions::DatasetAlreadyExists.new(tmp, parts.join('/')) if ret.empty?

      [last, ret]
    end

    # Return new Dataset object. Object is validated and exception
    # may be raised.
    def dataset_create_append_new(part, parent)
      new_ds = ::Dataset.new(
        name: part,
        user: ::User.current,
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
end
