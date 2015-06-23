class VpsAdmin::API::Resources::Location < HaveAPI::Resource
  version 1
  model ::Location
  desc 'Manage locations'

  params(:id) do
    id :id, label: 'ID', desc: 'Location ID', db_name: :location_id
  end

  params(:common) do
    string :label, label: 'Label', desc: 'Location label', db_name: :location_label
    bool :has_ipv6, label: 'Has IPv6', desc: 'True if location has IPv6 addresses',
         db_name: :location_has_ipv6
    bool :vps_onboot, label: 'VPS onboot', desc: 'Start all VPSes in this location on boot?',
         db_name: :location_vps_onboot
    string :remote_console_server, label: 'Remote console server', desc: 'URL to HTTP remote console server',
           db_name: :location_remote_console_server
    string :domain, label: 'Domain', desc: 'Location domain, subdomain at environment domain'
  end

  params(:all) do
    use :id
    use :common
  end

  class Index < HaveAPI::Actions::Default::Index
    desc 'List locations'

    input do
      resource VpsAdmin::API::Resources::Environment,
               desc: 'Filter locations having nodes in an environment'
    end

    output(:object_list) do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
      output whitelist: %i(id label)
      allow
    end

    example do
      request({})
      response({
        locations: {
            label: 'Prague',
            has_ipv6: true,
            vps_onboot: true,
            remote_console_server: 'https://console.vpsadmin.mydomain.com',
            domain: 'prg',
            created_at: '2014-05-04 16:59:52 +0200',
            updated_at: '2014-05-04 16:59:52 +0200'
        }
      })
    end

    def query
      q = ::Location

      if input[:environment]
        q = q.joins(:nodes).where(
            servers: {environment_id: input[:environment].id}
        ).group('locations.location_id')
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
        location: {
            label: 'Brno',
            has_ipv6: true,
            vps_onboot: true,
            remote_console_server: '',
            domain: 'brq'
        }
      })
      response({
        location: {
          id: 2
        }
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
      restrict whitelist: %i(id label)
      allow
    end

    example do
      request({})
      response({
        location: {
          id: 2,
          label: 'Brno',
          has_ipv6: true,
          vps_onboot: true,
          remote_console_server: '',
          domain: 'brq'
        }
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
      request({
        location: {
            label: 'Ostrava',
            has_ipv6: true,
            vps_onboot: true,
            remote_console_server: '',
            environment: 1,
            domain: 'ova'
        }
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
