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
      :time,
      keyword_init: true,
    )

    def initialize
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
      return if !enable? || pool.role != 0 || pool.refquota_check != 1 || pool.datasets.empty?

      min_avail_bytes = $CFG.get(:dataset_expander, :min_avail_bytes)
      min_avail_pct = $CFG.get(:dataset_expander, :min_avail_percent)

      pool.datasets.each_value do |ds|
        next unless ds.properties.has_key?('available')
        avail_bytes = ds.properties['available'].value
        next if avail_bytes.nil? # non-existent datasets found only in db

        refquota_bytes = ds.properties['refquota'].value
        next if refquota_bytes == 0 # no refquota is set, this should never happen

        if avail_bytes < min_avail_bytes \
            || ((avail_bytes.to_f / refquota_bytes) * 100) < min_avail_pct
          expand_dataset(ds, refquota_bytes: refquota_bytes)
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

        t = event.time.utc.strftime('%Y-%m-%d %H:%M:%S')

        db = Db.new
        db.prepared(
          'INSERT INTO dataset_expansion_events SET
            dataset_id = ?,
            original_refquota = ?,
            new_refquota = ?,
            added_space = ?,
            updated_at = ?,
            created_at = ?',
          event.dataset.id, event.original_refquota, event.new_refquota, event.added_space, t, t
        )
        db.close
      end
    end

    # @param ds [StorageStatus::Dataset]
    def expand_dataset(ds, refquota_bytes:)
      t = Time.now

      min_add_bytes = $CFG.get(:dataset_expander, :min_expand_bytes)
      min_add_pct = $CFG.get(:dataset_expander, :min_expand_percent)

      add_bytes = [
        min_add_bytes,
        ((min_add_pct / 100.0) * refquota_bytes).round,
      ].max

      new_refquota_bytes = refquota_bytes + add_bytes

      log(
        :info,
        "Expanding #{ds.name} #{humanize_data(refquota_bytes)} -> "+
        "#{humanize_data(new_refquota_bytes)} (+#{humanize_data(add_bytes)})"
      )

      rs = zfs(:set, "refquota=#{new_refquota_bytes}", ds.name, valid_rcs: :all)

      if rs.error?
        log(:warn, "Failed to expand #{ds.name}, exit status #{rs.exitstatus}: #{rs.output}")
        return
      end

      @submit_queue << Event.new(
        dataset: ds,
        original_refquota: (refquota_bytes / 1024.0 / 1024).round,
        new_refquota: (new_refquota_bytes / 1024.0 / 1024.0).round,
        added_space: (add_bytes / 1024.0 / 1024).round,
        time: t,
      )
    end
  end
end
