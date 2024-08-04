require 'vpsadmin/api/maintainable'

class Cluster
  include VpsAdmin::API::Maintainable::Model

  maintenance_children :environments

  def self.search(value)
    ret = []

    if /\A\d+\z/ =~ value
      id = value.to_i

      [::User, ::Vps, ::Export, ::TransactionChain].each do |klass|
        ret << {
          resource: klass.to_s,
          id: klass.find(id).id,
          attribute: :id,
          value: id
        }
      rescue ActiveRecord::RecordNotFound
        next
      end

      return ret
    end

    # If it is an IP address, try to compress it. The gem seems to compress only
    # IPv6 addresses though.
    begin
      addr = IPAddress.parse(value)
    rescue ArgumentError
      # ignore
    else
      value = addr.to_s
    end

    # Find which network the address belongs to
    if addr
      ip_v = addr.ipv4? ? 4 : 6

      ::Network.where(ip_version: ip_v).each do |net|
        next unless net.include?(addr)

        # Find a matching IP address
        # Quick check if addr is not an IpAddress itself before we walk through
        # network's all addresses
        ip_match = net.ip_addresses.find_by(ip_addr: addr.address, prefix: addr.prefix)

        if ip_match
          ret << { resource: 'IpAddress', id: ip_match.id, attribute: 'address', value: ip_match.to_s }
        else
          # Walk the addresses
          net.ip_addresses.each do |ip|
            next unless ip.include?(addr)

            ret << { resource: 'IpAddress', id: ip.id, attribute: 'address', value: ip.to_s }

            # Switch the search to the located ip in order to find the related
            # VPS and user.
            value = ip.ip_addr
            break
          end
        end

        ret << { resource: 'Network', id: net.id, attribute: 'network', value: net.to_s }
        break
      end
    end

    q = ActiveRecord::Base.connection.quote(value)
    ActiveRecord::Base.connection.execute(
      "SELECT 'User', id, 'login', login
      FROM users WHERE login = #{q}

      UNION
      SELECT 'User', id, 'full_name', full_name
      FROM users WHERE full_name = #{q} AND object_state < 3

      UNION
      SELECT 'User', id, 'email', email
      FROM users WHERE email = #{q} AND object_state < 3

      UNION
      SELECT 'User', user_id AS id, 'ip_addr', ip_addr
      FROM ip_addresses
      WHERE ip_addr = #{q} AND user_id IS NOT NULL

      UNION
      SELECT 'User', v.user_id AS id, 'ip_addr', ip_addr
      FROM ip_addresses i
      INNER JOIN network_interfaces n ON i.network_interface_id = n.id
      INNER JOIN vpses v ON n.vps_id = v.id
      WHERE ip_addr = #{q}

      UNION
      SELECT 'Vps', n.vps_id AS id, 'ip_addr', ip_addr
      FROM ip_addresses i
      INNER JOIN network_interfaces n ON i.network_interface_id = n.id
      WHERE i.ip_addr = #{q} AND n.vps_id IS NOT NULL

      UNION
      SELECT 'Vps', n.vps_id AS id, 'ip_addr', h.ip_addr
      FROM host_ip_addresses h
      INNER JOIN ip_addresses i ON h.ip_address_id = i.id
      INNER JOIN network_interfaces n ON i.network_interface_id = n.id
      WHERE h.ip_addr = #{q} AND n.vps_id IS NOT NULL

      UNION
      SELECT 'User', e.user_id AS id, 'ip_addr', ip_addr
      FROM ip_addresses i
      INNER JOIN network_interfaces n ON i.network_interface_id = n.id
      INNER JOIN exports e ON n.export_id = e.id
      WHERE ip_addr = #{q}

      UNION
      SELECT 'Export', n.export_id AS id, 'ip_addr', h.ip_addr
      FROM host_ip_addresses h
      INNER JOIN ip_addresses i ON h.ip_address_id = i.id
      INNER JOIN network_interfaces n ON i.network_interface_id = n.id
      WHERE h.ip_addr = #{q} AND n.export_id IS NOT NULL

      UNION
      SELECT 'Vps', id, 'hostname', hostname
      FROM vpses
      WHERE hostname = #{q} AND object_state < 3

      UNION
      SELECT 'User', id, 'login', login
      FROM users WHERE login LIKE CONCAT('%', #{q}, '%')

      UNION
      SELECT 'User', id, 'full_name', full_name
      FROM users WHERE full_name LIKE CONCAT('%', #{q}, '%') AND object_state < 3

      UNION
      SELECT 'User', id, 'email', email
      FROM users WHERE email LIKE CONCAT('%', #{q}, '%') AND object_state < 3

      UNION
      SELECT 'Vps', id, 'hostname', hostname
      FROM vpses
      WHERE hostname LIKE CONCAT('%', #{q}, '%') AND object_state < 3"
    ).each do |result|
      ret << { resource: result[0], id: result[1], attribute: result[2], value: result[3] }
    end

    ret
  end

  def environments
    ::Environment
  end
end
