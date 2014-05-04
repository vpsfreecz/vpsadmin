class VpsAdmin::API::Resources::Environment < VpsAdmin::API::Resource
  version 1
  model ::Environment
  desc 'Manage environments'

  class Index < VpsAdmin::API::Actions::Default::Index
    desc 'List environments'

    output(:environments) do
      list_of(:environments, {
        id: Integer,
        label: String,
        domain: String,
        created_at: String,
        updated_at: String
      })

      integer :id, label: 'ID', desc: 'Environment ID'
      string :label, desc: 'Environment label'
      string :domain, desc: 'Environment FQDN, should be subject\'s root domain'
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

end
