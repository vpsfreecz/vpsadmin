class VpsAdmin::API::Resources::Environment < VpsAdmin::API::Resource
  version 1
  model ::Environment
  desc 'Manage environments'

  params(:id) do
    integer :id, label: 'ID', desc: 'Environment ID'
  end

  params(:common) do
    string :label, desc: 'Environment label'
    string :domain, desc: 'Environment FQDN, should be subject\'s root domain'
  end

  params(:all) do
    use :id
    use :common
  end

  class Index < VpsAdmin::API::Actions::Default::Index
    desc 'List environments'

    output(:environments) do
      list_of_objects
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
      ret = []

      ::Environment.all.each do |env|
        ret << env.attributes
      end

      ret
    end
  end

  class Create < VpsAdmin::API::Actions::Default::Create
    desc 'Create new environment'

    input do
      use :common
    end

    output do
      use :id
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
      env = ::Environment.new(params[:environment])

      if env.save
        ok({id: env.id})
      else
        error('save failed', to_param_names(env.errors.to_hash, :input))
      end
    end
  end

  class Show < VpsAdmin::API::Actions::Default::Show
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

  class Update < VpsAdmin::API::Actions::Default::Update
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

  class Delete < VpsAdmin::API::Actions::Default::Delete
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

end
