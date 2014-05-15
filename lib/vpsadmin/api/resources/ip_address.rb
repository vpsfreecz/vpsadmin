class VpsAdmin::API::Resources::IpAddress < HaveAPI::Resource
  version 1
  model ::IpAddress
  desc 'Manage IP addresses'

  params(:id) do
    id :id, label: 'ID', desc: 'IP address ID', db_name: :ip_id
  end

  params(:filters) do
    foreign_key :vps_id, label: 'VPS ID', desc: 'VPS this IP is assigned to, might be null'
    integer :version, label: 'IP version', desc: '4 or 6', db_name: :ip_v
    foreign_key :location_id, label: 'Location ID',
              desc: 'Location this IP address is available in',
              db_name: :ip_location
  end

  params(:common) do
    use :filters
    string :addr, label: 'Address', desc: 'Address itself', db_name: :ip_addr
  end

  params(:all) do
    use :id
    use :common
  end

  class Index < HaveAPI::Actions::Default::Index
    desc 'List IP addresses'

    input(:ip_addresses) do
      use :filters
    end

    output(:ip_addresses) do
      list_of_objects
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
    end

    example do
      request({
        ip_addresses: {
          vps_id: 101
        }
      })
      response({
        ip_addresses: [
            {
                id: 10,
                vps_id: 101,
                version: 4,
                location_id: 1,
                addr: '192.168.0.50'
            }
        ]
      })
      comment 'List IP addresses assigned to VPS with ID 101.'
    end

    def exec
      ret = []

      ::IpAddress.where(to_db_names(params[:ip_addresses])).each do |ip|
        ret << to_param_names(ip.attributes)
      end

      ret
    end
  end
end
