require 'libosctl'
require 'nodectld/utils'

module NodeCtld
  class StorageStatus
    include OsCtl::Lib::Utils::Log

    PROPERTIES = %w(used referenced available)

    Pool = Struct.new(:name, :fs, :datasets, keyword_init: true)

    Dataset = Struct.new(:type, :name, :id, :properties, keyword_init: true)

    Property = Struct.new(:id, :name, :value, keyword_init: true)

    def initialize
      @pools = {}
    end

    def update(db)
      fetch(db)
      read
      save(db)
    end

    def log_type
      'storage-status'
    end

    protected
    def fetch(db)
      # Fetch pools
      rs = db.prepared(
        "SELECT id, filesystem FROM pools WHERE node_id = ?",
        $CFG.get(:vpsadmin, :node_id)
      )

      rs.each do |row|
        @pools[ row['id'] ] = Pool.new(
          name: row['filesystem'].split('/').first,
          fs: row['filesystem'],
          datasets: {},
        )
      end

      select_properties = PROPERTIES.map { |v| property_to_db(v) }

      @pools.each do |pool_id, pool|
        # Fetch datasets
        db.prepared(
          "SELECT d.full_name, dips.id, props.name AS p_name, props.id AS p_id
          FROM dataset_in_pools dips
          INNER JOIN datasets d ON d.id = dips.dataset_id
          INNER JOIN dataset_properties props ON props.dataset_in_pool_id = dips.id
          WHERE dips.pool_id = ? AND props.name IN (#{select_properties.map{'?'}.join(',')})",
          pool_id, *select_properties
        ).each do |row|
          prop_name = property_from_db(row['p_name'])
          next unless PROPERTIES.include?(prop_name)

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
              id: row['id'],
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
    end

    def read
      @pools.each_value do |pool|
        next if pool.datasets.empty?

        reader = OsCtl::Lib::Zfs::PropertyReader.new

        begin
          tree = reader.read(
            [pool.fs],
            PROPERTIES,
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

          PROPERTIES.each do |prop|
            ds_prop = ds.properties[prop]
            next if ds_prop.nil?

            ds_prop.value = (tree_ds.properties[prop].to_i / 1024.0 / 1024).round
          end
        end
      end
    end

    def save(db)
      @pools.each_value do |pool|
        pool.datasets.each_value do |ds|
          PROPERTIES.each do |prop|
            ds_prop = ds.properties[prop]
            next if ds_prop.nil? || ds_prop.value.nil?

            db.prepared(
              'UPDATE dataset_properties
              SET value = ?
              WHERE
                dataset_in_pool_id = ?
                AND
                name = ?',
              YAML.dump(ds_prop.value), ds.id, property_to_db(prop)
            )

            db.prepared(
              "INSERT INTO dataset_property_histories SET
              dataset_property_id = ?, value = ?, created_at = ?",
              ds_prop.id, ds_prop.value, Time.now.utc.strftime('%Y-%m-%d %H:%M:%S')
            )
          end
        end
      end
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
