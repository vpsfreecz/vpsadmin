class VpsAdmin::API::Resources::Location < HaveAPI::Resource
  model ::Location
  desc 'Manage locations'

  params(:id) do
    id :id, label: 'ID', desc: 'Location ID'
  end

  params(:common) do
    string :label, label: 'Label', desc: 'Location label'
    string :description, label: 'Description', desc: 'Location description'
    bool :has_ipv6, label: 'Has IPv6', desc: 'True if location has IPv6 addresses'
    bool :vps_onboot, label: 'VPS onboot', desc: 'Start all VPSes in this location on boot?'
    string :remote_console_server, label: 'Remote console server',
        desc: 'URL to HTTP remote console server'
    string :domain, label: 'Domain', desc: 'Location domain, subdomain at environment domain'
    resource VpsAdmin::API::Resources::Environment, label: 'Environment'
  end

  params(:all) do
    use :id
    use :common
  end

  class Index < HaveAPI::Actions::Default::Index
    desc 'List locations'

    input do
      resource VpsAdmin::API::Resources::Environment,
               desc: 'Filter locations by environment'
      bool :has_hypervisor, label: 'Has hypervisor',
        desc: 'List only locations having at least one hypervisor node'
      bool :has_storage, label: 'Has storage',
        desc: 'List only locations having at least one storage node'
      string :hypervisor_type,
        label: 'Hypervisor type',
        choices: %w(openvz vpsadminos),
        desc: 'List only locations having at least one node of this type'
      resource VpsAdmin::API::Resources::Location,
        name: :shares_v4_networks_with,
        label: 'Shares IPv4 networks with location'
      resource VpsAdmin::API::Resources::Location,
        name: :shares_v6_networks_with,
        label: 'Shares IPv4 networks with location'
      resource VpsAdmin::API::Resources::Location,
        name: :shares_any_networks_with,
        label: 'Shares IPv4 networks with location'
      bool :shares_networks_primary, label: 'Shared network primary',
        desc: 'Filter locations with shared networks that are primary in the other location'
    end

    output(:object_list) do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
      output whitelist: %i(id label description environment remote_console_server)
      allow
    end

    example do
      request({})
      response([{
        label: 'Prague',
        has_ipv6: true,
        vps_onboot: true,
        remote_console_server: 'https://console.vpsadmin.mydomain.com',
        domain: 'prg',
        created_at: '2014-05-04 16:59:52 +0200',
        updated_at: '2014-05-04 16:59:52 +0200'
      }])
    end

    def query
      q = ::Location

      if input[:environment]
        q = q.where(
            environment_id: input[:environment].id
        ).group('locations.id')
      end

      has = []
      not_has = []

      if input[:has_hypervisor]
        has << 'node'

      elsif input[:has_hypervisor] === false
        not_has << 'node'
      end

      if input[:has_storage]
        has << 'storage'

      elsif input[:has_storage] === false
        not_has << 'storage'
      end

      if has.size > 0
        q = q.joins(:nodes).where(
            nodes: {role: has}
        ).group('locations.id')
      end

      if not_has.size > 0
        q = q.joins(:nodes).where.not(
          nodes: {role: not_has}
        ).group('locations.id')
      end

      if input[:hypervisor_type]
        q = q.joins(:nodes).where(
          nodes: {hypervisor_type: ::Node.hypervisor_types[input[:hypervisor_type]]},
        ).group('locations.id')
      end

      if input[:shares_v4_networks_with]
        loc_ids = ::LocationNetwork
          .select('location_networks.location_id')
          .joins('INNER JOIN location_networks ln2')
          .joins('INNER JOIN networks ON location_networks.network_id = networks.id')
          .where('location_networks.location_id != ln2.location_id')
          .where('location_networks.network_id = ln2.network_id')
          .where('ln2.location_id = ?', input[:shares_v4_networks_with].id)
          .where('networks.ip_version = 4')

        case input[:shares_networks_primary]
        when true
          loc_ids = loc_ids.where('ln2.primary = 1')
        when false
          loc_ids = loc_ids.where('ln2.primary IS NULL')
        end

        q = q.where(id: loc_ids.pluck(:location_id))
      end

      if input[:shares_v6_networks_with]
        loc_ids = ::LocationNetwork
          .select('location_networks.location_id')
          .joins('INNER JOIN location_networks ln2')
          .joins('INNER JOIN networks ON location_networks.network_id = networks.id')
          .where('location_networks.location_id != ln2.location_id')
          .where('location_networks.network_id = ln2.network_id')
          .where('ln2.location_id = ?', input[:shares_v6_networks_with].id)
          .where('networks.ip_version = 6')

        case input[:shares_networks_primary]
        when true
          loc_ids = loc_ids.where('ln2.primary = 1')
        when false
          loc_ids = loc_ids.where('ln2.primary IS NULL')
        end

        q = q.where(id: loc_ids.pluck(:location_id))
      end

      if input[:shares_any_networks_with]
        loc_ids = ::LocationNetwork
          .select('location_networks.location_id')
          .joins('INNER JOIN location_networks ln2')
          .where('location_networks.location_id != ln2.location_id')
          .where('location_networks.network_id = ln2.network_id')
          .where('ln2.location_id = ?', input[:shares_any_networks_with].id)

        case input[:shares_networks_primary]
        when true
          loc_ids = loc_ids.where('ln2.primary = 1')
        when false
          loc_ids = loc_ids.where('ln2.primary IS NULL')
        end

        q = q.where(id: loc_ids.pluck(:location_id))
      end

      q
    end

    def count
      query.count
    end

    def exec
      with_includes(query).limit(input[:limit]).offset(input[:offset])
    end
  end

  class Create < HaveAPI::Actions::Default::Create
    desc 'Create new location'

    input do
      use :common
    end

    output do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
    end

    example do
      request({
        label: 'Brno',
        has_ipv6: true,
        vps_onboot: true,
        remote_console_server: '',
        domain: 'brq'
      })
      response({
        id: 2
      })
    end

    def exec
      loc = ::Location.new(to_db_names(params[:location]))

      if loc.save
        ok(loc)
      else
        error('save failed', to_param_names(loc.errors.to_hash, :input))
      end
    end
  end

  class Show < HaveAPI::Actions::Default::Show
    desc 'Show location'

    output do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
      restrict whitelist: %i(id label description environment remote_console_server)
      allow
    end

    example do
      path_params(2)
      request({})
      response({
        id: 2,
        label: 'Brno',
        has_ipv6: true,
        vps_onboot: true,
        remote_console_server: '',
        domain: 'brq'
      })
    end

    def exec
      ::Location.find(params[:location_id])
    end
  end

  class Update < HaveAPI::Actions::Default::Update
    desc 'Update location'

    input do
      use :common
    end

    authorize do |u|
      allow if u.role == :admin
    end

    example do
      path_params(2)
      request({
        label: 'Ostrava',
        has_ipv6: true,
        vps_onboot: true,
        remote_console_server: '',
        environment: 1,
        domain: 'ova'
      })
      response({})
    end

    def exec
      loc = ::Location.find(params[:location_id])

      if loc.update(to_db_names(params[:location]))
        ok
      else
        error('update failed', to_param_names(loc.errors.to_hash))
      end
    end
  end

  # class Delete < HaveAPI::Actions::Default::Delete
  #   desc 'Delete location'
  #
  #   authorize do |u|
  #     allow if u.role == :admin
  #   end
  #
  #   example do
  #     request({})
  #     response({})
  #   end
  #
  #   def exec
  #     ::Location.find(params[:location_id]).destroy
  #   end
  # end

  include VpsAdmin::API::Maintainable::Action
end
