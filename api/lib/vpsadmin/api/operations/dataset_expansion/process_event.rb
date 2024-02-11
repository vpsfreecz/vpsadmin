require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  # Process dataset expansion event
  #
  # If the event is invalid, nil is returned. In case the dataset is currently
  # locked, exception {::ResourceLocked} is raised. Otherwise, new
  # {::DatasetExpansion} is created and returned.
  class Operations::DatasetExpansion::ProcessEvent < Operations::Base
    # @param event [::DatasetExpansionEvent]
    # @param max_over_refquota_seconds [Integer]
    # @raise [::ResourceLocked]
    # @return [::DatasetExpansion, nil]
    def run(event, max_over_refquota_seconds:)
      if event.dataset.nil?
        event.destroy!
        return
      end

      ds = event.dataset
      exp = nil

      begin
        dip = ds.primary_dataset_in_pool!
      rescue ActiveRecord::RecordNotFound
        event.destroy!
        return
      end

      dip.acquire_lock do
        ActiveRecord::Base.transaction do
          orig_quota = dip.diskspace

          dip.reallocate_resource!(
            :diskspace,
            event.new_refquota,
            user: ds.user,
            override: true,
            lock_type: 'no_lock',
            save: true
          )

          prop = dip.dataset_properties.find_by!(name: 'refquota')
          prop.update!(value: event.new_refquota)

          if ds.dataset_expansion.nil?
            free_diskspace = ds.user.user_cluster_resources.joins(:cluster_resource).find_by!(
              environment: dip.pool.node.location.environment,
              cluster_resources: { name: 'diskspace' }
            ).free

            over_limit = free_diskspace < 0

            exp = ::DatasetExpansion.create!(
              vps: ds.root.primary_dataset_in_pool!.vpses.take!,
              dataset: ds,
              state: over_limit ? 'active' : 'resolved',
              original_refquota: orig_quota,
              added_space: event.added_space,
              max_over_refquota_seconds: max_over_refquota_seconds
            )

            ds.update!(dataset_expansion: exp) if over_limit
          else
            exp = ds.dataset_expansion

            exp.added_space += event.added_space
            exp.save!
          end

          exp.dataset_expansion_histories.create!(
            original_refquota: event.original_refquota,
            new_refquota: event.new_refquota,
            added_space: event.added_space,
            created_at: event.created_at,
            updated_at: event.updated_at
          )

          event.destroy!
        end
      end

      exp
    end
  end
end
