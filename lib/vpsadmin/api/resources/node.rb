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
    resource VpsAdmin::API::Resources::Location, label: 'Location',
             desc: 'Location node is placed in'
    resource VpsAdmin::API::Resources::Environment, label: 'Environment'
    string :availstat, label: 'Availability stats', desc: 'HTML code with availability graphs',
           db_name: :server_availstat
    string :ip_addr, label: 'IPv4 address', desc: 'Node\'s IP address', db_name: :server_ip4
    string :net_interface, label: 'Network interface', desc: 'Outgoing network interface'
    integer :max_tx, label: 'Max tx', desc: 'Maximum output throughput'
    integer :max_rx, label: 'Max tx', desc: 'Maximum input throughput'
  end

  params(:all) do
    use :id
    use :common
  end

  class Index < HaveAPI::Actions::Default::Index
    desc 'List nodes'

    input do
      resource VpsAdmin::API::Resources::Location, label: 'Location',
               desc: 'Location node is placed in'
      resource VpsAdmin::API::Resources::Environment, label: 'Environment'
    end

    output(:object_list) do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
      output whitelist: %i(id name location environment)
      allow
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
          environment: {
              id: 1,
              label: 'Production'
          },
          availstat: '',
          ip_addr: '192.168.0.10',
          maintenance: false
        }
      })
    end

    def query
      q = ::Node
      q = q.where(location: input[:location]) if input[:location]
      q = q.where(environment: input[:environment]) if input[:environment]
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
    desc 'Create new node'

    input do
      use :common
      patch :name, required: true
      patch :type, required: true
      patch :location, required: true
      patch :environment, required: true
      patch :ip_addr, required: true
    end

    output do
      use :all
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
          environment: 1,
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
      node = ::Node.new(to_db_names(input))

      if node.save
        ok(node)
      else
        error('save failed', to_param_names(node.errors.to_hash, :input))
      end
    end
  end

  class OverviewList < HaveAPI::Action
    desc 'List all nodes with some additional information'
    route 'overview_list'
    http_method :get

    output(:object_list) do
      use :all
      datetime :last_report, label: 'Last report'
      float :loadavg, label: 'Load'
      integer :vps_running, label: 'Running VPS', desc: 'Number of running VPSes'
      integer :vps_stopped, label: 'Stopped VPS', desc: 'Number of stopped VPSes'
      integer :vps_deleted, label: 'Deleted VPS', desc: 'Number of lazily deleted VPSes'
      integer :vps_total, label: 'Total VPS', desc: 'Total number of VPSes'
      integer :vps_free, label: 'Free VPS slots', desc: 'Number of free VPS slots'
      integer :vps_max, label: 'Max VPS slots', desc: 'Number of running VPSes'
      string :version, label: 'Version', desc: 'vpsAdmind version', db_name: :daemon_version
      string :kernel, label: 'Kernel', desc: 'Kernel version', db_name: :kernel_version
    end

    output(&VpsAdmin::API::Maintainable::Action.output_params)

    authorize do |u|
      allow if u.role == :admin
    end

    def exec
      ::Node.includes(:node_status).joins(:location).all
        .order('environment_id, locations.location_id, server_id')
    end
  end

  class PublicStatus < HaveAPI::Action
    desc 'Public node status'
    auth false

    output(:object_list) do
      bool :status, label: 'Status'
      string :name, label: 'Node name', db_name: :domain_name
      resource VpsAdmin::API::Resources::Location, label: 'Location',
               desc: 'Location node is placed in'
      datetime :last_report, label: 'Last report'
      integer :vps_count, label: 'VPS count', db_name: :vps_running
      integer :vps_free, label: 'Free VPS slots'
    end

    output(&VpsAdmin::API::Maintainable::Action.output_params)

    authorize do
      allow
    end

    def exec
      ::Node.includes(:location, :node_status).joins(:location).all
        .order('environment_id, locations.location_id, servers.server_id')
    end
  end

  class Show < HaveAPI::Actions::Default::Show
    desc 'Show node'

    output do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
      output whitelist: %i(id name location environment)
      allow
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
          environment: {
              id: 1,
              label: 'Production'
          },
          availstat: '',
          ip_addr: '192.168.0.11',
          maintenance: false
        }
      })
    end

    def prepare
      @node = ::Node.find(params[:node_id])
    end

    def exec
      @node
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
          location: 1,
          environment: 1,
          availstat: '',
          ip_addr: '192.168.0.11',
          maintenance: false
        }
      })
      response({})
    end

    def exec
      node = ::Node.find(params[:node_id])

      if node.update(to_db_names(input))
        ok
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

  include VpsAdmin::API::Maintainable::Action
end
