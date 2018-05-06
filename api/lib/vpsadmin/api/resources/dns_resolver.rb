class VpsAdmin::API::Resources::DnsResolver < HaveAPI::Resource
  model ::DnsResolver
  desc 'Manage DNS resolvers'

  params(:id) do
    id :id, label: 'ID', desc: 'DNS resolver ID'
  end

  params(:common) do
    string :ip_addr, label: 'IP address', desc: 'Multiple addresses separated by comma',
           db_name: :addrs
    string :label, label: 'Label'
    bool :is_universal, label: 'Is universal?',
         desc: 'Universal resolver is independent on location'
    resource VpsAdmin::API::Resources::Location, label: 'Location',
             desc: 'Location this resolver can be used on'
  end

  params(:all) do
    use :id
    use :common
  end

  class Index < HaveAPI::Actions::Default::Index
    desc 'List DNS resolvers'

    input do
      resource VpsAdmin::API::Resources::VPS, label: 'VPS',
          desc: 'List DNS resolvers usable for a specific VPS'
    end

    output(:object_list) do
      use :all
    end

    authorize do |u|
      allow
    end

    example do
      request({})
      response({
        dns_resolvers: [{
          id: 26,
          ip_addr: '8.8.8.8',
          label: 'Google DNS',
          is_universal: true,
          location: nil
        }]
      })
    end

    def query
      q = ::DnsResolver.all

      if input[:vps]
        q = q.where(
          'location_id = ? OR is_universal = 1',
          input[:vps].node.location_id
        )
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

  class Show < HaveAPI::Actions::Default::Show
    desc 'Show DNS resolver'

    output do
      use :all
    end

    authorize do |u|
      allow
    end

    def prepare
      @dns_resolver = ::DnsResolver.find(params[:dns_resolver_id])
    end

    def exec
      @dns_resolver
    end
  end

  class Create < HaveAPI::Actions::Default::Create
    desc 'Create a DNS resolver'

    input do
      use :common
      patch :ip_addr, required: true
      patch :label, required: true
      patch :is_universal, required: true
    end

    output do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
    end

    def exec
      ::DnsResolver.create!(to_db_names(input))

    rescue ActiveRecord::RecordInvalid => e
      error('create failed', to_param_names(e.record.errors.to_hash, :input))
    end
  end

  class Update < HaveAPI::Actions::Default::Update
    input do
      use :common
    end

    output do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
    end

    def exec
      ns = ::DnsResolver.find(params[:dns_resolver_id])
      ns.update(to_db_names(input))

    rescue ActiveRecord::RecordInvalid => e
      error('update failed', to_param_names(e.record.errors.to_hash, :input))
    end
  end

  class Delete < HaveAPI::Actions::Default::Delete
    input do
      bool :force, label: 'Force deletion',
           desc: 'Delete the DNS resolver even it is in use. Affected VPSes get a new DNS resolver.'
    end

    authorize do |u|
      allow if u.role == :admin
    end

    def exec
      ns = ::DnsResolver.find(params[:dns_resolver_id])

      if !input[:force] && ns.in_use?
        error('The DNS resolver is in use. Use force=true to override.')
      end

      ns.delete

    rescue ActiveRecord::RecordInvalid => e
      error('update failed', to_param_names(e.record.errors.to_hash, :input))
    end
  end
end
