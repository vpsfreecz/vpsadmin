module VpsAdmind
  class StorageStatus
    include Utils::Log
    include Utils::System
    include Utils::Zfs

    PROPERTIES = [:used, :referenced, :available]

    def self.update(db)
      o = new(db)
      o.fetch
      o.read
      o.update
      o
    end

    def initialize(db)
      @db = db
      @pools = {}
      @objects = []
    end

    def fetch
      # Fetch pools
      st = @db.prepared_st(
          "SELECT id, filesystem FROM pools WHERE node_id = ?",
          $CFG.get(:vpsadmin, :server_id)
      )

      st.each do |row|
        @pools[ row[0] ] = {
            :fs => row[1],
            :objects => []
        }
      end

      st.close

      @pools.each do |pool_id, pool|
        # Fetch datasets
        @db.query("
            SELECT d.full_name, dips.id
            FROM dataset_in_pools dips
            INNER JOIN datasets d ON d.id = dips.dataset_id
            WHERE dips.pool_id = #{pool_id}
        ").each_hash do |row|
          pool[:objects] << {
              :type => :filesystem,
              :name => row['full_name'],
              :object_id => row['id'].to_i
          }
        end

        # FIXME: Fetch snapshots - not yet
        next

        # This code may be used in the future, when properties of snapshots are tracked
        # as well.
        @db.query("
            SELECT d.full_name, s.name, sips.id
            FROM snapshot_in_pools sips
            INNER JOIN dataset_in_pools dips ON dips.id = sips.dataset_in_pool_id
            INNER JOIN datasets d ON d.id = dips.dataset_id
            INNER JOIN snapshots s ON s.id = sips.snapshot_id
            WHERE dips.pool_id = #{pool_id}
        ").each_hash do |row|
          pool[:objects] << {
              :type => :snapshot,
              :name => "#{row['full_name']}@#{row['name']}",
              :object_id => row['id'].to_i
          }
        end
      end
    end

    def read
      @pools.each_value do |pool|
        zfs(
            :get,
            "-Hrp -t filesystem -o name,property,value #{PROPERTIES.join(',')}",
            pool[:fs]
        )[:output].split("\n").each do |prop|
          parts = prop.split
          next if parts[0] == pool[:fs]

          name = parts[0].sub(/^#{pool[:fs]}\//, '')

          # Skip pool's internal datasets
          next if name.start_with?('vpsadmin/') || name == 'vpsadmin'

          i = pool[:objects].index do |v|
            v[:name] == name
          end

          unless i
            log(:warn, :regular, "'#{parts[0]}' not registered in the database")
            next
          end

          pool[:objects][i][ parts[1].to_sym ] = parts[2].to_i / 1024 / 1024
        end

      end

    rescue CommandFailed => e
      p e
    end

    def update
      @pools.each_value do |pool|
        pool[:objects].each do |obj|
          PROPERTIES.each do |p|
            next unless obj[p]

            col = obj[:type] == :filesystem ? 'dataset_in_pool_id' : 'snapshot_in_pool_id'

            @db.query("
                UPDATE dataset_properties
                SET value = '#{YAML.dump(obj[p])}'
                WHERE
                  #{col} = #{obj[:object_id]}
                  AND
                  name = '#{translate_property(p)}'
            ")
          end
        end
      end
    end

    def translate_property(p)
      return 'avail' if p == :available
      p
    end
  end
end
