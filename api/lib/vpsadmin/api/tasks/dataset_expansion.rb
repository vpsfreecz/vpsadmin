module VpsAdmin::API::Tasks
  class DatasetExpansion < Base
    DEADLINE = ENV['DEADLINE'] ? ENV['DEADLINE'].to_i : 30*24*60*60

    COOLDOWN = ENV['COOLDOWN'] ? ENV['COOLDOWN'].to_i : 2*60*60

    MAX_EXPANSIONS = ENV['MAX_EXPANSIONS'] ? ENV['MAX_EXPANSIONS'].to_i : 3

    OVERQUOTA_MB = ENV['OVERQUOTA_MB'] ? ENV['OVERQUOTA_MB'].to_i : 5*1024

    FREE_PERCENT = ENV['FREE_PERCENT'] ? ENV['FREE_PERCENT'].to_i : 5

    FREE_MB = ENV['FREE_MB'] ? ENV['FREE_MB'].to_i : 1024

    # Process new dataset expansion events
    #
    # Accepts the following environment variables:
    # [DEADLINE]: Number of seconds within which the user should free space
    def process_events
      ::DatasetExpansionEvent.all.each do |event|
        if event.dataset.nil?
          event.destroy!
          next
        end

        ds = event.dataset
        exp = nil

        begin
          dip = ds.primary_dataset_in_pool!
        rescue ActiveRecord::RecordNotFound
          event.destroy!
          next
        end

        begin
          dip.acquire_lock do
            ActiveRecord::Base.transaction do
              orig_quota = dip.diskspace

              dip.reallocate_resource!(
                :diskspace,
                event.new_refquota,
                user: ds.user,
                override: true,
                lock_type: 'no_lock',
                save: true,
              )

              prop = dip.dataset_properties.find_by!(name: 'refquota')
              prop.update!(value: event.new_refquota)

              if ds.dataset_expansion.nil?
                free_diskspace = ds.user.user_cluster_resources.joins(:cluster_resource).find_by!(
                  environment: dip.pool.node.location.environment,
                  cluster_resources: {name: 'diskspace'},
                ).free

                over_limit = free_diskspace < 0

                exp = ::DatasetExpansion.create!(
                  dataset: ds,
                  state: over_limit ? 'active' : 'resolved',
                  original_refquota: orig_quota,
                  added_space: event.added_space,
                  deadline: Time.now + DEADLINE,
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
                updated_at: event.updated_at,
              )

              event.destroy!
            end
          end
        rescue ResourceLocked
          warn "Dataset in pool id=#{dip.id} name=#{ds.full_name} locked"
          next
        end
      end
    end

    # Stop VPS that are over quota too much or too long
    #
    # Accepts the following environment variables:
    # [MAX_EXPANSIONS]: VPS with more than `MAX_EXPANSIONS` are suspended
    # [OVERQUOTA_MB]: Number of MiB to be over the original quota
    # [COOLDOWN]: Number of seconds between VPS stops
    def stop_vps
      now = Time.now

      ::DatasetExpansion.where(state: 'active', stop_vps: true).each do |exp|
        if exp.dataset.referenced - OVERQUOTA_MB > exp.original_refquota \
           && (exp.last_vps_stop.nil? || exp.last_vps_stop + COOLDOWN < now) \
           && vps.uptime >= COOLDOWN \
           && \
             (exp.dataset_expansion_histories.count > MAX_EXPANSIONS \
             || (exp.deadline && exp.deadline < Time.now))
          begin
            vps = exp.dataset.root.primary_dataset_in_pool!.vpses.where(object_state: 'active').take!
          rescue ActiveRecord::RecordNotFound
            next
          end

          if vps.is_running?
            begin
              TransactionChains::Vps::StopOverQuota.fire(vps, exp)
              puts "Stopped VPS #{vps.id}"
              exp.update!(last_vps_stop: now)
            rescue ResourceLocked
              warn "VPS #{vps.id} is locked, unable to stop at this time"
              next
            end
          end
        end
      end
    end

    # Shrink expaded datasets to their original size if possible
    #
    # Accepts the following environment variables:
    # [COOLDOWN]: Number of seconds between shrink retries
    # [FREE_PERCENT]: How much free space must there be to try shrinking
    # [FREE_MB]: How much free space must there be to try shrinking
    def resolve_datasets
      now = Time.now

      ::DatasetExpansion.where(state: 'active').each do |exp|
        begin
          dip = exp.dataset.primary_dataset_in_pool!
        rescue ActiveRecord::RecordNotFound
          warn "No primary dataset in pool for dataset id=#{exp.dataset_id} full_name=#{exp.dataset.full_name}"
          next
        end

        if (exp.last_shrink.nil? || exp.last_shrink + COOLDOWN < now) \
           && exp.created_at + COOLDOWN < now \
           && dip.referenced + FREE_MB < exp.original_refquota \
           && (dip.referenced.to_f / exp.original_refquota) * 100 <= (100 - FREE_PERCENT)
          TransactionChains::Dataset::Shrink.fire(dip, exp)
          exp.update!(last_shrink: now)
        end
      end
    end
  end
end
