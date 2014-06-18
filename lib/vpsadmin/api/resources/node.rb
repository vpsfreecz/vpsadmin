class VpsAdmin::API::Resources::Node < HaveAPI::Resource
  version 1
  model ::Node
  desc 'Manage nodes'

  params(:id) do
    id :id, label: 'ID', desc: 'Node ID', db_name: :server_id
  end

  params(:common) do
    string :name, label: 'Name', desc: 'Node name', db_name: :server_name
    string :type, label: 'Role', desc: 'node, storage or mailer', db_name: :server_type
    resource VpsAdmin::API::Resources::Location, label: 'Location', desc: 'Location node is placed in'
    string :availstat, label: 'Availability stats', desc: 'HTML code with availability graphs',
           db_name: :server_availstat
    string :ip_addr, label: 'IPv4 address', desc: 'Node\'s IP address', db_name: :server_ip4
    bool :maintenance, label: 'Maintenance mode', desc: 'Toggle maintenance mode for this node',
         db_name: :server_maintenance
  end

  params(:all) do
    use :id
    use :common
  end

  class Index < HaveAPI::Actions::Default::Index
    desc 'List nodes'

    output(:list) do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
    end

    example do
      request({})
      response({
        nodes: {
          id: 1,
          name: 'node1',
          type: 'node',
          location: {
              id: 1,
              label: 'The Location'
          },
          availstat: '',
          ip_addr: '192.168.0.10',
          maintenance: false
        }
      })
    end

    def exec
      ret = []

      ::Node.all.limit(params[:node][:limit]).offset(params[:node][:offset]).each do |node|
        ret << to_param_names(node.attributes, :output)
      end

      ret
    end
  end

  class Create < HaveAPI::Actions::Default::Create
    desc 'Create new node'

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
        node: {
          name: 'node2',
          type: 'node',
          location: 1,
          availstat: '',
          ip_addr: '192.168.0.11',
          maintenance: false
        }
      })
      response({
        node: {
          id: 2
        }
      })
    end

    def exec
      node = ::Node.new(to_db_names(params[:node]))

      if node.save
        ok({id: node.server_id})
      else
        error('save failed', to_param_names(node.errors.to_hash, :input))
      end
    end
  end

  class Show < HaveAPI::Actions::Default::Show
    desc 'Show node'

    output do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
    end

    example do
      request({})
      response({
        node: {
          id: 2,
          name: 'node2',
          type: 'node',
          location: {
              id: 1,
              label: 'The Location'
          },
          availstat: '',
          ip_addr: '192.168.0.11',
          maintenance: false
        }
      })
    end

    def exec
      to_param_names(::Node.find(params[:node_id]).attributes)
    end
  end

  class Update < HaveAPI::Actions::Default::Update
    desc 'Update node'

    input do
      use :common
    end

    authorize do |u|
      allow if u.role == :admin
    end

    example do
      request({
        node: {
          name: 'node2',
          type: 'storage',
          location: {
              id: 1,
              label: 'The Location'
          },
          availstat: '',
          ip_addr: '192.168.0.11',
          maintenance: false
        }
      })
      response({})
    end

    def exec
      node = ::Node.find(params[:node_id])

      if node.update(to_db_names(params[:node]))
        ok({})
      else
        error('update failed', to_param_names(node.errors.to_hash, :input))
      end
    end
  end

  class Delete < HaveAPI::Actions::Default::Delete
    desc 'Delete node'

    authorize do |u|
      allow if u.role == :admin
    end

    example do
      request({})
      response({})
    end

    def exec
      ::Node.find(params[:node_id]).destroy
    end
  end
end
