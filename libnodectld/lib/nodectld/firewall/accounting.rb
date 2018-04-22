require 'libosctl'
require 'nodectld/firewall/accounting_role'

module NodeCtld::Firewall
  class Accounting
    include OsCtl::Lib::Utils::Log

    ROLES = %i(public private)

    attr_reader :fw, *ROLES

    def initialize(fw)
      @fw = fw
      @roles = []

      ROLES.each do |r|
        acc = AccountingRole.new(fw, r)
        @roles << acc

        instance_variable_set("@#{r}", acc)
      end
    end

    def init(db, v)
      @roles.each { |r| r.init(db, v) }
    end

    def reg_ip(addr, prefix, v)
      @fw.synchronize do
        @roles.each { |r| r.reg_ip(addr, prefix, v) }
      end
    end

    def unreg_ip(addr, prefix, v)
      @fw.synchronize do
        @roles.each { |r| r.unreg_ip(addr, prefix, v) }
      end
    end

    def fetch_traffic
      ret = {}

      @roles.each do |acc|
        acc.update_traffic do |ip, proto, traffic|
          ret[ip] ||= default_ip_record
          ret[ip][acc.role][proto] = traffic
        end
      end

      ret
    end

    def update_traffic(db)
      time = Time.now
      traffic = fetch_traffic

      @fw.ip_map.synchronize do
        # First iteration, update live traffic monitors
        traffic.each do |ip, roles|
          addr = @fw.ip_map[ip]

          unless addr
            log(:warn, :firewall, "IP '#{ip}' not found in IP map")
            next
          end

          addr.monitor.update(roles, time: time)
          addr.monitor.save(db)
        end

        # Second iteration, log traffic
        traffic.each do |ip, roles|
          addr = @fw.ip_map[ip]
          next unless addr

          save_ip_traffic(db, addr, roles)
        end
      end
    end

    def save_ip_traffic(db, addr, roles)
      roles.each do |role, protocols|
        protocols.each do |proto, t|
          next if t[:packets][:in] == 0 && t[:packets][:out] == 0

          db.prepared(
              "INSERT INTO ip_recent_traffics SET
                ip_address_id = ?, user_id = ?, protocol = ?, role = ?,
                packets_in = ?, packets_out = ?,
                bytes_in = ?, bytes_out = ?,
                created_at = CONVERT_TZ(NOW(), 'Europe/Prague', 'UTC')
              ON DUPLICATE KEY UPDATE
                packets_in = packets_in + values(packets_in),
                packets_out = packets_out + values(packets_out),
                bytes_in = bytes_in + values(bytes_in),
                bytes_out = bytes_out + values(bytes_out)",
              addr.id, addr.user_id, AccountingRole::PROTOCOL_MAP.index(proto),
              ROLES.index(role),
              t[:packets][:in] || 0, t[:packets][:out] || 0,
              t[:bytes][:in] || 0, t[:bytes][:out] || 0
          )
        end
      end
    end

    def cleanup
      @roles.each { |r| r.cleanup }
    end

    protected
    def default_ip_record
      ret = {}

      ROLES.each do |r|
        ret[r] = {}

        AccountingRole::PROTOCOLS.each do |p|
          ret[r][p] = {
            packets: {in: 0, out: 0},
            bytes: {in: 0, out: 0},
          }
        end
      end

      ret
    end
  end
end
