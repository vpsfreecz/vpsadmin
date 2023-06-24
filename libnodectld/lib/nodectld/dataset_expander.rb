require 'libosctl'
require 'yaml'

module NodeCtld
  class DatasetExpander
    include OsCtl::Lib::Utils::Log
    include OsCtl::Lib::Utils::System
    include OsCtl::Lib::Utils::Humanize

    Dataset = Struct.new(
      :id,
      :name,
      keyword_init: true,
    )

    Event = Struct.new(
      :dataset,
      :original_refquota,
      :new_refquota,
      :added_space,
      :time,
      keyword_init: true,
    )

    def initialize
      @worker_queue = OsCtl::Lib::Queue.new
      @update_queue = OsCtl::Lib::Queue.new
      @submit_queue = OsCtl::Lib::Queue.new
      @mutex = Mutex.new
      @datasets = {}
      @init = false
    end

    def enable?
      $CFG.get(:dataset_expander, :enable)
    end

    def start
      @worker = Thread.new { run_worker }
      @updater = Thread.new { run_updater }
      @submitter = Thread.new { run_submitter }
      nil
    end

    def stop
      [@worker_queue, @update_queue, @submit_queue].each { |q| q << :stop }
      [@worker, @updater, @submitter].each { |t| t.join }
      nil
    end

    def log_type
      'dataset-expander'
    end

    protected
    def run_worker
      v = @worker_queue.pop
      fail "unexpected command #{v.inspect}" unless %i(start stop).include?(v)

      loop do
        v = @worker_queue.pop(timeout: $CFG.get(:dataset_expander, :check_interval))
        return if v == :stop

        check_datasets
      end
    end

    def run_updater
      loop do
        v = @update_queue.pop(timeout: $CFG.get(:dataset_expander, :update_interval))
        return if v == :stop

        update_datasets

        unless @init
          @init = false
          @worker_queue << :start
        end
      end
    end

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

    def update_datasets
      datasets = {}
      db = Db.new

      db.prepared(
        "SELECT ds.id, ds.full_name, pools.filesystem
        FROM dataset_in_pools dips
        INNER JOIN pools ON pools.id = dips.pool_id
        INNER JOIN datasets ds ON ds.id = dips.dataset_id
        WHERE
          pools.node_id = ?
          AND pools.role = 0
          AND pools.refquota_check = 1
          AND dips.confirmed = 1",
        $CFG.get(:vpsadmin, :node_id)
      ).each do |row|
        name = File.join(row['filesystem'], row['full_name'])
        datasets[name] = Dataset.new(
          id: row['id'],
          name: name,
        )
      end

      db.close

      @mutex.synchronize { @datasets = datasets }
    end

    def check_datasets
      datasets = @mutex.synchronize { @datasets }

      if datasets.empty?
        log(:info, 'No datasets to check')
        return
      end

      log(:info, "Checking available space on #{datasets.length} datasets")

      reader = OsCtl::Lib::Zfs::PropertyReader.new
      tree = reader.read(
        datasets.keys,
        %w(refquota available),
        ignore_error: true,
      )

      min_avail_bytes = $CFG.get(:dataset_expander, :min_avail_bytes)
      min_avail_pct = $CFG.get(:dataset_expander, :min_avail_percent)

      tree.each_tree_dataset do |tree_ds|
        next unless tree_ds.properties.has_key?('available')
        avail_bytes = tree_ds.properties['available'].to_i

        refquota_bytes = tree_ds.properties['refquota'].to_i
        next if refquota_bytes == 0 # no refquota is set, this should never happen

        ds = datasets[tree_ds.name]

        if avail_bytes < min_avail_bytes \
            || ((avail_bytes.to_f / refquota_bytes) * 100) < min_avail_pct
          expand_dataset(ds, refquota_bytes: refquota_bytes)
        end
      end
    end

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
