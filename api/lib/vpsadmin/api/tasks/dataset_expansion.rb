module VpsAdmin::API::Tasks
  class DatasetExpansion < Base
    MAX_OVER_REFQUOTA_SECONDS = ENV['MAX_OVER_REFQUOTA_SECONDS'] ? ENV['MAX_OVER_REFQUOTA_SECONDS'].to_i : 30 * 24 * 60 * 60

    COOLDOWN = ENV['COOLDOWN'] ? ENV['COOLDOWN'].to_i : 2 * 60 * 60

    MAX_EXPANSIONS = ENV['MAX_EXPANSIONS'] ? ENV['MAX_EXPANSIONS'].to_i : 3

    STRICT_MAX_EXPANSIONS = ENV['STRICT_MAX_EXPANSIONS'] ? ENV['STRICT_MAX_EXPANSIONS'].to_i : 9

    OVERQUOTA_MB = ENV['OVERQUOTA_MB'] ? ENV['OVERQUOTA_MB'].to_i : 5 * 1024

    STRICT_OVERQUOTA_MB = ENV['STRICT_OVERQUOTA_MB'] ? ENV['STRICT_OVERQUOTA_MB'].to_i : 100 * 1024

    FREE_PERCENT = ENV['FREE_PERCENT'] ? ENV['FREE_PERCENT'].to_i : 5

    FREE_MB = ENV['FREE_MB'] ? ENV['FREE_MB'].to_i : 1024

    # Process new dataset expansion events
    #
    # Accepts the following environment variables:
    # [MAX_OVER_REFQUOTA_SECONDS]: Number of seconds within which the user should free space
    def process_events
      expansions = []

      ::DatasetExpansionEvent.all.each do |event|
        begin
          exp = VpsAdmin::API::Operations::DatasetExpansion::ProcessEvent.run(
            event,
            max_over_refquota_seconds: MAX_OVER_REFQUOTA_SECONDS
          )
        rescue ResourceLocked
          warn "Dataset id=#{event.dataset_id} name=#{event.dataset.full_name} locked"
          next
        end

        next if exp.nil?

        expansions << exp if exp.enable_notifications && exp.vps.active? && !expansions.detect { |v| v.id == exp.id }
      end

      expansions.each do |exp|
        TransactionChains::Mail::VpsDatasetExpanded.fire(exp)
      end
    end

    # Stop VPS that are over quota too much or too long
    #
    # Accepts the following environment variables:
    # [MAX_EXPANSIONS]: VPS with more than `MAX_EXPANSIONS` are stopped
    # [STRICT_MAX_EXPANSIONS]: VPS with more than `STRICT_MAX_EXPANSIONS` are suspended
    # [OVERQUOTA_MB]: Number of MiB to be over the original quota for VPS to be stopped
    # [STRICT_OVERQUOTA_MB]: Number of MiB to be over the original quota for VPS to be suspended
    # [COOLDOWN]: Number of seconds between VPS stops
    def stop_vps
      now = Time.now

      ::DatasetExpansion
        .joins(:vps)
        .where(state: 'active', stop_vps: true)
        .where(vpses: { object_state: ::Vps.object_states[:active] })
        .each do |exp|
        exp_cnt = exp.expansion_count

        if exp.vps.active? && exp.dataset.referenced > exp.original_refquota
          elapsed_time =
            if exp.last_over_refquota_check
              now - exp.last_over_refquota_check
            else
              0
            end

          exp.update!(
            over_refquota_seconds: exp.over_refquota_seconds + elapsed_time,
            last_over_refquota_check: now
          )
        end

        if exp_cnt > STRICT_MAX_EXPANSIONS \
           && exp.vps.active? \
           && exp.dataset.referenced - STRICT_OVERQUOTA_MB > exp.original_refquota
          begin
            exp.vps.set_object_state(
              :suspended,
              reason: "Dataset #{exp.dataset.full_name} expanded too many times"
            )
            puts "Suspended VPS #{exp.vps.id} due to too many expansions (#{exp_cnt})"
          rescue ResourceLocked
            warn "VPS #{exp.vps.id} is locked, unable to suspend at this time"
          end

          next
        end

        # rubocop:disable Style/Next
        if exp.dataset.referenced - OVERQUOTA_MB > exp.original_refquota \
           && (exp.last_vps_stop.nil? || exp.last_vps_stop + COOLDOWN < now) \
           && exp.vps.active? \
           && exp.vps.is_running? \
           && exp.vps.uptime \
           && exp.vps.uptime >= COOLDOWN \
           && (exp_cnt > MAX_EXPANSIONS || exp.over_refquota_seconds > exp.max_over_refquota_seconds)
          begin
            TransactionChains::Vps::StopOverQuota.fire(exp)
            puts "Stopped VPS #{exp.vps.id}"
            exp.update!(last_vps_stop: now)
          rescue ResourceLocked
            warn "VPS #{exp.vps.id} is locked, unable to stop at this time"
            next
          end
        end
        # rubocop:enable Style/Next
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

      ::DatasetExpansion
        .joins(:vps)
        .where(state: 'active', enable_shrink: true)
        .where(vpses: { object_state: ::Vps.object_states[:active] })
        .each do |exp|
        begin
          dip = exp.dataset.primary_dataset_in_pool!
        rescue ActiveRecord::RecordNotFound
          warn "No primary dataset in pool for dataset id=#{exp.dataset_id} full_name=#{exp.dataset.full_name}"
          next
        end

        next unless (exp.last_shrink.nil? || exp.last_shrink + COOLDOWN < now) \
           && exp.created_at + COOLDOWN < now \
           && dip.referenced + FREE_MB < exp.original_refquota \
           && (dip.referenced.to_f / exp.original_refquota) * 100 <= (100 - FREE_PERCENT)

        TransactionChains::Vps::ShrinkDataset.fire(dip, exp)
        exp.update!(last_shrink: now)
      end
    end
  end
end
