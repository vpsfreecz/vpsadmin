require 'libosctl'
require 'yaml'

module NodeCtld
  class DatasetExpander
    include OsCtl::Lib::Utils::Log
    include OsCtl::Lib::Utils::System
    include OsCtl::Lib::Utils::Humanize

    Event = Struct.new(
      :dataset,
      :original_refquota,
      :new_refquota,
      :added_space,
      :time
    )

    def initialize
      @channel = NodeBunny.create_channel
      @exchange = @channel.direct(NodeBunny.exchange_name)
      @submit_queue = OsCtl::Lib::Queue.new
    end

    def enable?
      $CFG.get(:dataset_expander, :enable)
    end

    def start
      @submitter = Thread.new { run_submitter }
      nil
    end

    def stop
      @submit_queue << :stop
      @submitter.join
      nil
    end

    # @param pool [StorageStatus::Pool]
    def check(pool)
      return if !enable? || pool.role != 'hypervisor' || !pool.refquota_check || pool.datasets.empty?

      min_avail_bytes = $CFG.get(:dataset_expander, :min_avail_bytes)
      min_avail_pct = $CFG.get(:dataset_expander, :min_avail_percent)
      min_pool_avail_bytes = $CFG.get(:dataset_expander, :min_pool_avail_bytes)
      min_pool_avail_pct = $CFG.get(:dataset_expander, :min_pool_avail_percent)

      if pool.used_bytes.nil? || pool.available_bytes.nil?
        log(
          :warn,
          "Skipping dataset auto-expansion on #{pool.fs}, pool space metrics are unavailable"
        )
        return
      end

      pool.datasets.each_value do |ds|
        next unless ds.properties.has_key?('available')

        avail_bytes = ds.properties['available'].value
        next if avail_bytes.nil? # non-existent datasets found only in db

        refquota_bytes = ds.properties['refquota'].value
        next if refquota_bytes == 0 # no refquota is set, this should never happen

        next unless avail_bytes < min_avail_bytes \
                    || ((avail_bytes.to_f / refquota_bytes) * 100) < min_avail_pct

        add_bytes = expansion_size(refquota_bytes)
        pool_total = pool.used_bytes + pool.available_bytes
        pool_min_avail = [
          min_pool_avail_bytes,
          ((min_pool_avail_pct / 100.0) * pool_total).round
        ].max
        remaining_after = pool.available_bytes - add_bytes

        if remaining_after < pool_min_avail
          log(
            :info,
            "Skipping expansion of #{ds.name}, pool #{pool.fs} would have " \
            "#{humanize_data(remaining_after)} free, below minimum " \
            "#{humanize_data(pool_min_avail)}"
          )
          next
        end

        if expand_dataset(ds, refquota_bytes:, add_bytes:)
          pool.used_bytes += add_bytes
          pool.available_bytes -= add_bytes
        end
      end
    end

    def log_type
      'dataset-expander'
    end

    protected

    def run_submitter
      loop do
        event = @submit_queue.pop
        return if event == :stop

        NodeBunny.publish_wait(
          @exchange,
          {
            dataset_id: event.dataset.id,
            original_refquota: event.original_refquota,
            new_refquota: event.new_refquota,
            added_space: event.added_space,
            time: event.time.to_i
          }.to_json,
          persistent: true,
          content_type: 'application/json',
          routing_key: 'dataset_expansions'
        )
      end
    end

    # @param ds [StorageStatus::Dataset]
    def expand_dataset(ds, refquota_bytes:, add_bytes:)
      t = Time.now
      new_refquota_bytes = refquota_bytes + add_bytes

      log(
        :info,
        "Expanding #{ds.name} #{humanize_data(refquota_bytes)} -> " \
        "#{humanize_data(new_refquota_bytes)} (+#{humanize_data(add_bytes)})"
      )

      rs = zfs(:set, "refquota=#{new_refquota_bytes}", ds.name, valid_rcs: :all)

      if rs.error?
        log(:warn, "Failed to expand #{ds.name}, exit status #{rs.exitstatus}: #{rs.output}")
        return false
      end

      @submit_queue << Event.new(
        dataset: ds,
        original_refquota: (refquota_bytes / 1024.0 / 1024).round,
        new_refquota: (new_refquota_bytes / 1024.0 / 1024.0).round,
        added_space: (add_bytes / 1024.0 / 1024).round,
        time: t
      )
      true
    end

    def expansion_size(refquota_bytes)
      min_add_bytes = $CFG.get(:dataset_expander, :min_expand_bytes)
      min_add_pct = $CFG.get(:dataset_expander, :min_expand_percent)

      [
        min_add_bytes,
        ((min_add_pct / 100.0) * refquota_bytes).round
      ].max
    end
  end
end
