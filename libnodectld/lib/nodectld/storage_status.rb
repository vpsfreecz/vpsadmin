require 'libosctl'
require 'nodectld/utils'

module NodeCtld
  class StorageStatus
    include OsCtl::Lib::Utils::Log

    READ_PROPERTIES = %w[used referenced available refquota compressratio refcompressratio]

    SAVE_PROPERTIES = %w[used referenced available compressratio refcompressratio]

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

      @channel = NodeBunny.create_channel
      @exchange = @channel.direct(NodeBunny.exchange_name)
      @message_id = 0
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

        # Prevent queue from piling up when supervisor is down
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

      RpcClient.run do |rpc|
        rpc.list_pools.each do |pool|
          next unless %w[primary hypervisor].include?(pool['role'])

          pools[ pool['id'] ] = Pool.new(
            name: pool['name'],
            fs: pool['filesystem'],
            role: pool['role'],
            refquota_check: pool['refquota_check'],
            datasets: {}
          )
        end

        select_properties = READ_PROPERTIES.map { |v| property_to_db(v) }

        pools.each do |pool_id, pool|
          rpc.list_pool_dataset_properties(pool_id, select_properties).each do |prop|
            prop_name = property_from_db(prop['property_name'])
            next unless READ_PROPERTIES.include?(prop_name)

            name = File.join(pool.fs, prop['dataset_name'])

            if ds = pool.datasets[name]
              ds.properties[prop_name] = Property.new(
                id: prop['property_id'],
                name: prop_name,
                value: nil
              )

            else
              pool.datasets[name] = Dataset.new(
                type: :filesystem,
                name: name,
                id: prop['dataset_id'],
                dip_id: prop['dataset_in_pool_id'],
                properties: {
                  prop_name => Property.new(
                    id: prop['property_id'],
                    name: prop_name,
                    value: nil
                  )
                }
              )
            end
          end
        end
      end

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
            recursive: true
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

            ds_prop.value = parse_value(prop, tree_ds.properties[prop])
          end
        end

        @dataset_expander.check(pool)
      end
    end

    def save(pools)
      now = Time.now
      max_size = $CFG.get(:storage, :batch_size)
      to_save = []

      pools.each_value do |pool|
        pool.datasets.each_value do |ds|
          SAVE_PROPERTIES.each do |prop|
            ds_prop = ds.properties[prop]
            next if ds_prop.nil? || ds_prop.value.nil?

            to_save << {
              id: ds_prop.id,
              name: ds_prop.name,
              value: ds_prop.value
            }
          end

          save_properties(now, to_save) if to_save.length >= max_size
        end
      end

      return unless to_save.any?

      save_properties(now, to_save)
    end

    def save_properties(time, to_save)
      NodeBunny.publish_wait(
        @exchange,
        {
          message_id: @message_id,
          time: time.to_i,
          properties: to_save
        }.to_json,
        content_type: 'application/json',
        routing_key: 'storage_statuses'
      )

      to_save.clear

      @message_id += 1
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

    def parse_value(prop, v)
      case prop
      when 'compressratio', 'refcompressratio'
        v.to_f
      else
        v.to_i
      end
    end
  end
end
