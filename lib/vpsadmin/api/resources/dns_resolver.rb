class VpsAdmin::API::Resources::DnsResolver < HaveAPI::Resource
  version 1
  model ::DnsResolver
  desc 'Manage DNS resolvers'

  params(:id) do
    id :id, label: 'ID', desc: 'DNS resolver ID', db_name: :dns_id
  end

  params(:common) do
    string :ip_addr, label: 'IP address', desc: 'Multiple addresses separated by comma',
           db_name: :dns_ip
    string :label, label: 'Label', db_name: :dns_label
    bool :is_universal, label: 'Is universal?',
         desc: 'Universal resolver is independent on location',
         db_name: :dns_is_universal
    resource VpsAdmin::API::Resources::Location, label: 'Location',
             desc: 'Location this resolver can be used on',
             value_params: ->{ @dns_resolver.dns_location }
  end

  params(:all) do
    use :id
    use :common
  end

  class Index < HaveAPI::Actions::Default::Index
    desc 'List DNS resolvers'

    output(:list) do
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

    def exec
      ret = []

      ::DnsResolver.all.limit(params[:dns_resolver][:limit]).offset(params[:dns_resolver][:offset]).each do |dns|
        ret << to_param_names(all_attrs(dns), :output)
      end

      ret
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
      to_param_names(all_attrs(@dns_resolver))
    end
  end
end
