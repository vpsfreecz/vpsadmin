require 'vpsadmin/api/maintainable'

class Cluster
  include VpsAdmin::API::Maintainable::Model

  maintenance_children :environments

  def self.search(v)
    if /\A\d+\z/ =~ v
      ret = []
      id = v.to_i

      [::User, ::Vps].each do |klass|
        begin
          ret << {
            resource: klass.to_s,
            id: klass.find(id).id,
            attribute: :id,
            value: id,
          }

        rescue ActiveRecord::RecordNotFound
          next
        end
      end

      return ret
    end

    q = ActiveRecord::Base.connection.quote(v)
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
      WHERE i.ip_addr = #{q}

      UNION
      SELECT 'Vps', n.vps_id AS id, 'ip_addr', h.ip_addr
      FROM host_ip_addresses h
      INNER JOIN ip_addresses i ON h.ip_address_id = i.id
      INNER JOIN network_interfaces n ON i.network_interface_id = n.id
      WHERE h.ip_addr = #{q}

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
    ).map do |v|
      {resource: v[0], id: v[1], attribute: v[2], value: v[3]}
    end
  end

  def environments
    ::Environment
  end
end
