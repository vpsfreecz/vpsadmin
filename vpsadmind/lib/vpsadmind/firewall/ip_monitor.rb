require 'pp'

module VpsAdmind::Firewall
  class IpMonitor
    attr_reader :delta

    def initialize(addr)
      @addr = addr
      @last_data = []
    end

    def update(roles, time: nil)
      time ||= Time.now
      @cols = {}
      @delta = @last_update ? time.to_i - @last_update.to_i : 0
      @last_update = time

      roles.each do |role, protocols|
        protocols.each do |proto, stats|
          proto = :other if proto == :all

          stats.each do |stat, dirs|
            dirs.each do |dir, v|
              add_value(v, role, proto, stat, dir)
            end
          end

          add_sums([role, proto], stats)
        end

        add_sums([role], protocols)
      end

      add_sums([], roles)
    end

    def save(db)
      return unless changed?

      db.query("
          INSERT INTO ip_traffic_live_monitors SET
            ip_address_id = #{@addr.id},
            #{@cols.map { |k, v| "#{k} = #{v}" }.join(",\n")},
            updated_at = CONVERT_TZ(NOW(), 'Europe/Prague', 'UTC'),
            delta = #{@delta}
          ON DUPLICATE KEY UPDATE
            #{@cols.keys.map { |v| "#{v} = values(#{v})" }.join(",\n") },
            updated_at = values(updated_at),
            delta = values(delta)
      ")

      @last_data = @cols.values
    end

    def get(name, field, dir)
      @cols[ (name + [field, dir]).join('_') ]
    end

    def changed?
      @last_data != @cols.values
    end

    protected
    def add_value(v, *name)
      add_column(name.join('_'), v)
    end

    def add_sums(name, hash)
      %i(packets bytes).each do |stat|
        sum_in = recursive_sum(hash, stat, :in)
        sum_out = recursive_sum(hash, stat, :out)

        add_value(sum_in, *(name + [stat, :in]))
        add_value(sum_out, *(name + [stat, :out]))
        add_value(sum_in + sum_out, *(name + [stat]))
      end
    end

    def add_column(name, value)
      @cols[name] = value
    end

    def recursive_sum(hash, field, dir)
      n = 0

      hash.each do |k, v|
        if %i(packets bytes).include?(k) && k != field
          next

        elsif v.is_a?(::Hash)
          n += recursive_sum(v, field, dir)

        elsif k == dir
          n += v
        end
      end

      n
    end
  end
end
