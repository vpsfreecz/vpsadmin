require 'libosctl'
require 'nodectld/utils'

module NodeCtld
  class StorageStatus
    include OsCtl::Lib::Utils::Log

    READ_PROPERTIES = %w(used referenced available refquota)

    SAVE_PROPERTIES = %w(used referenced available)

    Pool = Struct.new(:name, :fs, :role, :refquota_check, :datasets, keyword_init: true)

    Dataset = Struct.new(:type, :name, :id, :dip_id, :properties, keyword_init: true)

    Property = Struct.new(:id, :name, :value, keyword_init: true)

    # @param dataset_expander [DatasetExpander]
    def initialize(dataset_expander)
      @dataset_expander = dataset_expander
      @mutex = Mutex.new
      @update_queue = OsCtl::Lib::Queue.new
      @read_queue = OsCtl::Lib::Queue.new
      @submit_queue = OsCtl::Lib::Queue.new
      @pools = {}
      @last_log = nil
    end

    def enable?
      $CFG.get(:storage, :update_status)
    end

    def start
      @reader = Thread.new { run_reader }
      @updater = Thread.new { run_updater }
      @submitter = Thread.new { run_submitter }
      nil
    end

    def stop
      @stop = true
      [@read_queue, @update_queue, @submit_queue].each { |q| q << :stop }
      [@reader, @updater, @submitter].each { |t| t.join }
      nil
    end

    def update
      @update_queue << :update
    end

    def log_type
      'storage-status'
    end

    protected
    def run_reader
      loop do
        v = @read_queue.pop(timeout: $CFG.get(:storage, :status_interval))
        return if v == :stop

        pools = @mutex.synchronize { @pools }
        read(pools)

        # Prevent queue from piling up when db server is down
        @submit_queue.clear if @submit_queue.length > 1

        @submit_queue << pools
      end
    end

    def run_updater
      loop do
        v = @update_queue.pop(timeout: $CFG.get(:storage, :update_interval))
        return if v == :stop

        pools = fetch
        @mutex.synchronize { @pools = pools }
        @read_queue << :read
      end
    end

    def run_submitter
      loop do
        v = @submit_queue.pop
        return if v == :stop || @stop

        pools = v
        save(pools)
      end
    end

    def fetch
      pools = {}
      db = Db.new

      # Fetch pools
      rs = db.prepared(
        "SELECT id, filesystem, role, refquota_check FROM pools WHERE node_id = ?",
        $CFG.get(:vpsadmin, :node_id)
      )

      rs.each do |row|
        pools[ row['id'] ] = Pool.new(
          name: row['filesystem'].split('/').first,
          fs: row['filesystem'],
          role: row['role'],
          refquota_check: row['refquota_check'],
          datasets: {},
        )
      end

      select_properties = READ_PROPERTIES.map { |v| property_to_db(v) }

      pools.each do |pool_id, pool|
        # Fetch datasets
        db.prepared(
          "SELECT
            d.full_name,
            dips.id AS dip_id,
            d.id AS dataset_id,
            props.name AS p_name,
            props.id AS p_id
          FROM dataset_in_pools dips
          INNER JOIN datasets d ON d.id = dips.dataset_id
          INNER JOIN dataset_properties props ON props.dataset_in_pool_id = dips.id
          WHERE
            dips.pool_id = ?
            AND dips.confirmed = 1
            AND props.name IN (#{select_properties.map{'?'}.join(',')})",
          pool_id, *select_properties
        ).each do |row|
          prop_name = property_from_db(row['p_name'])
          next unless READ_PROPERTIES.include?(prop_name)

          name = File.join(pool.fs, row['full_name'])

          if ds = pool.datasets[name]
            ds.properties[prop_name] = Property.new(
              id: row['p_id'],
              name: prop_name,
              value: nil,
            )

          else
            pool.datasets[name] = Dataset.new(
              type: :filesystem,
              name: name,
              id: row['dataset_id'],
              dip_id: row['dip_id'],
              properties: {
                prop_name => Property.new(
                  id: row['p_id'],
                  name: prop_name,
                  value: nil,
                ),
              },
            )
          end
        end
      end

      db.close
      pools
    end

    def read(pools)
      pools.each_value do |pool|
        next if pool.datasets.empty?

        reader = OsCtl::Lib::Zfs::PropertyReader.new

        begin
          tree = reader.read(
            [pool.fs],
            READ_PROPERTIES,
            recursive: true,
          )
        rescue SystemCommandFailed => e
          log(:warn, "Failed to get status of pool #{pool.fs}: #{e.output}")
          next
        end

        vpsadmin_prefix = File.join(pool.fs, 'vpsadmin')

        tree.each_tree_dataset do |tree_ds|
          next if tree_ds.name.nil? || tree_ds.name == pool.name || tree_ds.name == pool.fs

          # Skip pool's internal datasets
          next if tree_ds.name.start_with?("#{vpsadmin_prefix}/") || tree_ds.name == vpsadmin_prefix

          ds = pool.datasets[tree_ds.name]

          if ds.nil?
            log(:warn, "'#{tree_ds.name}' not registered in the database")
            next
          end

          READ_PROPERTIES.each do |prop|
            ds_prop = ds.properties[prop]
            next if ds_prop.nil?

            ds_prop.value = tree_ds.properties[prop].to_i
          end
        end

        @dataset_expander.check(pool)
      end
    end

    def save(pools)
      now = Time.now
      db = Db.new
      save_log = @last_log.nil? || @last_log + $CFG.get(:storage, :log_interval) < now
      @last_log = now if save_log

      pools.each_value do |pool|
        pool.datasets.each_value do |ds|
          SAVE_PROPERTIES.each do |prop|
            ds_prop = ds.properties[prop]
            next if ds_prop.nil? || ds_prop.value.nil?

            save_val = (ds_prop.value / 1024.0 / 1024).round

            db.prepared(
              'UPDATE dataset_properties
              SET value = ?
              WHERE
                dataset_in_pool_id = ?
                AND
                name = ?',
              YAML.dump(save_val), ds.dip_id, property_to_db(prop)
            )

            if save_log
              db.prepared(
                "INSERT INTO dataset_property_histories SET
                dataset_property_id = ?, value = ?, created_at = ?",
                ds_prop.id, save_val, Time.now.utc.strftime('%Y-%m-%d %H:%M:%S')
              )
            end
          end
        end
      end

      db.close
    end

    def property_from_db(prop)
      case prop
      when 'avail'
        'available'
      else
        prop
      end
    end

    def property_to_db(prop)
      case prop
      when 'available'
        'avail'
      else
        prop
      end
    end
  end
end
