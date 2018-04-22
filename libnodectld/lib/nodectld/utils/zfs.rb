module NodeCtld
  # Utilities for zfs
  module Utils::Zfs
    class DatasetInfo
      Property = Struct.new(:source, :value)

      INHERIT_EXCEPTIONS = [:quota, :refquota, :canmount]

      def initialize(cmd, str)
        @cmd = cmd
        @props = {}

        str.split("\n").each do |line|
          prop = line.split("\t")

          @props[ prop[0].to_sym ] = Property.new(prop[1].to_sym, prop[2])
        end
      end

      def method_missing(name)
        if @props.has_key?(name)
          return @props[name].value
        end

        super(name)
      end

      def apply_to(ds)
        @props.each do |name, prop|
          case prop.source
            when :local, :none
              @cmd.zfs(:set, "#{name}=\"#{translate_value(name, prop.value)}\"", ds)

            when :default, :inherited
              next if INHERIT_EXCEPTIONS.include?(name)

              @cmd.zfs(:inherit, name, ds)
            else
              # :temporary, nothing to do
          end
        end
        true
      end

      def translate_value(k, v)
        return 'none' if [:quota, :refquota].include?(k) && v.to_i == 0
        v
      end
    end

    def list_snapshots(ds)
      zfs(:list, "-r -t snapshot -H -o name", ds)[:output].split()
    end

    def dataset_properties(ds, names)
      DatasetInfo.new(self, zfs(
        :get,
        "-H -p -o property,source,value #{names.is_a?(Array) ? names.join(',') : names}",
        ds
      )[:output])
    end

    def get_confirmed_snapshot_name(db, snap_id)
      db.prepared('SELECT name FROM snapshots WHERE id = ?', snap_id).get!['name']
    end

    def translate_property(k, v)
      if v === true
        'on'

      elsif v === false
        'off'

      elsif v.nil?
        'none'

      else
        if %w(quota refquota).include?(k)
          if v == 0
            'none'
          else
            "#{v}M"
          end

        else
          v
        end
      end
    end
  end
end
