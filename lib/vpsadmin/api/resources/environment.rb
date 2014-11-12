class VpsAdmin::API::Resources::Environment < HaveAPI::Resource
  version 1
  model ::Environment
  desc 'Manage environments'

  params(:id) do
    integer :id, label: 'ID', desc: 'Environment ID'
  end

  params(:common) do
    string :label, desc: 'Environment label'
    string :domain, desc: 'Environment FQDN, should be subject\'s root domain'
    bool :can_create_vps, label: 'Can create a VPS', default: false
    bool :can_destroy_vps, label: 'Can destroy a VPS', default: false
    integer :vps_lifetime, label: 'Default VPS lifetime',
            desc: 'in seconds, 0 is unlimited', default: 0
  end

  params(:all) do
    use :id
    use :common
  end

  class Index < HaveAPI::Actions::Default::Index
    desc 'List environments'

    output(:object_list) do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
    end

    example do
      request({})
      response({
        environments: [
            {
              id: 1,
              label: 'Production',
              domain: 'vpsfree.cz',
              created_at: '2014-05-04 16:59:52 +0200',
              updated_at: '2014-05-04 16:59:52 +0200',
            }
          ]
       })
    end

    def exec
      ::Environment.all.limit(params[:environment][:limit]).offset(params[:environment][:offset])
    end
  end

  class Create < HaveAPI::Actions::Default::Create
    desc 'Create new environment'

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
        environment: {
          label: 'Devel',
          domain: 'vpsfree.cz'
        }
      })
      response({
        environment: {
          id: 2
        }
      })
    end

    def exec
      env = ::Environment.new(input)

      if env.save
        ok(env)
      else
        error('save failed', to_param_names(env.errors.to_hash, :input))
      end
    end
  end

  class Show < HaveAPI::Actions::Default::Show
    desc 'Show environment'

    output do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
    end

    example do
      request({})
      response({
        environment: {
          id: 1,
          label: 'Production',
          domain: 'vpsfree.cz',
          created_at: '2014-05-04 16:59:52 +0200',
          updated_at: '2014-05-04 16:59:52 +0200',
        }
      })
    end

    def exec
      ::Environment.find(params[:environment_id]).attributes
    end
  end

  class Update < HaveAPI::Actions::Default::Update
    desc 'Update environment'

    input do
      use :common
    end

    authorize do |u|
      allow if u.role == :admin
    end

    example do
      request({
        label: 'My new name',
        domain: 'new.domain'
      })
      response({})
    end

    def exec
      env = ::Environment.find(params[:environment_id])

      if env.update(params[:environment])
        ok({})
      else
        error('update failed', env.errors.to_hash)
      end
    end
  end

  class Delete < HaveAPI::Actions::Default::Delete
    desc 'Delete environment'

    authorize do |u|
      allow if u.role == :admin
    end

    example do
      request({})
      response({})
    end

    def exec
      ::Environment.find(params[:environment_id]).destroy
    end
  end

  include VpsAdmin::API::Maintainable::Action

  class ConfigChain < HaveAPI::Resource
    version 1
    route ':environment_id/config_chains'
    desc 'Manage implicit VPS config chains'
    model ::EnvironmentConfigChain

    params(:all) do
      resource VpsAdmin::API::Resources::VpsConfig, label: 'VPS config'
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List environment VPS config chain'

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def query
        ::EnvironmentConfigChain.where(
            environment: ::Environment.find(params[:environment_id])
        ).order('cfg_order')
      end

      def count
        query.count
      end

      def exec
        with_includes(query).limit(input[:limit]).offset(input[:offset])
      end
    end

    class Replace < HaveAPI::Action
      desc 'Set complete config chain'
      http_method :post

      input(:object_list) do
        use :all
        patch :vps_config, required: true
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        ::Environment.find(params[:environment_id]).set_config_chain(
            input.map { |v| v[:vps_config] }
        )
        ok
      end
    end
  end
end
