class VpsAdmin::API::Resources::Node < HaveAPI::Resource
  model ::Node
  desc 'Manage nodes'

  params(:id) do
    id :id, label: 'ID', desc: 'Node ID', db_name: :server_id
  end

  params(:common) do
    string :name, label: 'Name', desc: 'Node name', db_name: :server_name
    string :domain_name, label: 'Domain name',
      desc: 'Node name including location domain'
    string :type, label: 'Role', desc: 'node, storage or mailer', db_name: :server_type
    resource VpsAdmin::API::Resources::Location, label: 'Location',
             desc: 'Location node is placed in'
    string :availstat, label: 'Availability stats', desc: 'HTML code with availability graphs',
           db_name: :server_availstat
    string :ip_addr, label: 'IPv4 address', desc: 'Node\'s IP address', db_name: :server_ip4
    string :net_interface, label: 'Network interface', desc: 'Outgoing network interface'
    integer :max_tx, label: 'Max tx', desc: 'Maximum output throughput'
    integer :max_rx, label: 'Max tx', desc: 'Maximum input throughput'

    integer :cpus
    integer :total_memory
    integer :total_swap

    # Hypervisor-specific params
    integer :max_vps
    string :ve_private
  end

  params(:status) do
    integer :uptime, label: 'Uptime'
    float :loadavg
    integer :process_count, label: 'Process count'
    float :cpu_user
    float :cpu_nice
    float :cpu_system
    float :cpu_idle
    float :cpu_iowait
    float :cpu_irq
    float :cpu_softirq
    float :cpu_guest
    float :loadavg
    integer :used_memory, label: 'Used memory', desc: 'in MB'
    integer :used_swap, label: 'Used swap', desc: 'in MB'
    integer :arc_c_max
    integer :arc_c
    integer :arc_size
    integer :arc_hitpercent
    string :version, db_name: :vpsadmind_version
    string :kernel
  end

  params(:all) do
    use :id
    use :common
    use :status
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
      output whitelist: %i(id name domain_name location)
      allow
    end

    example do
      request({})
      response([{
          id: 1,
          name: 'node1',
          type: 'node',
          location: {
              id: 1,
              label: 'The Location'
          },
          availstat: '',
          ip_addr: '192.168.0.10',
          maintenance_lock: 'no'
      }])
    end

    def query
      q = ::Node
      q = q.where(location: input[:location]) if input[:location]
      
      if input[:environment]
        q = q.joins(:location).where(
            locations: {environment_id: input[:environment].id}
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

  class Create < HaveAPI::Actions::Default::Create
    desc 'Create a new node'

    input do
      use :all, include: %i(id name type location ip_addr net_interface max_tx
                            max_rx max_vps ve_private cpus total_memory total_swap)
      patch :name, required: true
      patch :type, required: true
      patch :location, required: true
      patch :ip_addr, required: true
      patch :net_interface, required: true
      patch :cpus, required: true
      patch :total_memory, required: true
      patch :total_swap, required: true
      bool :maintenance, desc: 'Put the node into maintenance mode'
    end

    output do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
    end

    def exec
      ::Node.register!(to_db_names(input))
    
    rescue ActiveRecord::RecordInvalid => e
      error('save failed', to_param_names(e.record.errors.to_hash, :input))
    end
  end

  class OverviewList < HaveAPI::Action
    desc 'List all nodes with some additional information'
    route 'overview_list'
    http_method :get

    output(:object_list) do
      use :all
      datetime :last_report, label: 'Last report'
      integer :vps_running, label: 'Running VPS', desc: 'Number of running VPSes'
      integer :vps_stopped, label: 'Stopped VPS', desc: 'Number of stopped VPSes'
      integer :vps_deleted, label: 'Deleted VPS', desc: 'Number of lazily deleted VPSes'
      integer :vps_total, label: 'Total VPS', desc: 'Total number of VPSes'
      integer :vps_free, label: 'Free VPS slots', desc: 'Number of free VPS slots'
      integer :vps_max, label: 'Max VPS slots', desc: 'Number of running VPSes'
    end

    output(&VpsAdmin::API::Maintainable::Action.output_params)

    authorize do |u|
      allow if u.role == :admin
    end

    def exec
      with_includes.includes(:node_current_status).joins(:location).all
        .order('locations.environment_id, locations.location_id, servers.server_id')
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
      string :kernel, label: 'Kernel'
      float :cpu_idle, label: 'CPU idle'
    end

    output(&VpsAdmin::API::Maintainable::Action.output_params)

    authorize do
      allow
    end

    def exec
      ::Node.includes(:location, :node_current_status).joins(:location).all
        .order('locations.environment_id, locations.location_id, servers.server_id')
    end
  end

  class Show < HaveAPI::Actions::Default::Show
    desc 'Show node'

    output do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
      output whitelist: %i(id name domain_name location)
      allow
    end

    example do
      url_params(2)
      request({})
      response({
          id: 2,
          name: 'node2',
          type: 'node',
          location: {
              id: 1,
              label: 'The Location'
          },
          availstat: '',
          ip_addr: '192.168.0.11',
          maintenance_lock: 'no'
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
      input blacklist: %i(type location)
      allow if u.role == :admin
    end

    example do
      url_params(2)
      request({
          name: 'node2',
          type: 'storage',
          location: 1,
          availstat: '',
          ip_addr: '192.168.0.11',
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

  # class Delete < HaveAPI::Actions::Default::Delete
  #   desc 'Delete node'
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
  #     ::Node.find(params[:node_id]).destroy
  #   end
  # end

  class Evacuate < HaveAPI::Action
    desc 'Evacuate node'
    route ':%{resource}_id/evacuate'
    http_method :post

    input do
      resource VpsAdmin::API::Resources::Node, name: :dst_node,
          label: 'Target node', required: true
      bool :stop_on_error, label: 'Stop on error', default: true,
          fill: true
      bool :outage_window, desc: 'Run migrations in every VPS\'s outage window',
          default: true, fill: true
      integer :concurrency, desc: 'How many migrations run concurrently', default: 1, fill: true
      bool :cleanup_data, default: true
      bool :send_mail, default: true
      string :reason
    end

    output(:hash) do
      id :migration_plan_id
    end

    authorize do |u|
      allow if u.role == :admin
    end

    def exec
      n = ::Node.find(params[:node_id])
      dst = input[:dst_node]

      if n.server_location != dst.server_location
        error('the destination node is in a different location')

      elsif n.location.environment_id != dst.location.environment_id
        error('the destination node is in a different environment')
      end

      plan = n.evacuate(input)

      {migration_plan_id: plan.id}
    end
  end

  include VpsAdmin::API::Maintainable::Action
  
  class Status < HaveAPI::Resource
    desc 'View node statuses in time'
    route ':node_id/statuses'
    model ::NodeStatus

    params(:all) do
      id :id
      integer :uptime, label: 'Uptime'
      float :loadavg
      integer :process_count, label: 'Process count'
      integer :cpus
      float :cpu_user
      float :cpu_nice
      float :cpu_system
      float :cpu_idle
      float :cpu_iowait
      float :cpu_irq
      float :cpu_softirq
      float :cpu_guest
      float :loadavg
      integer :total_memory
      integer :used_memory, label: 'Used memory', desc: 'in MB'
      integer :total_swap
      integer :used_swap, label: 'Used swap', desc: 'in MB'
      integer :arc_c_max
      integer :arc_c
      integer :arc_size
      float :arc_hitpercent
      string :version, db_name: :vpsadmind_version
      string :kernel
      datetime :created_at
    end
  
    class Index < HaveAPI::Actions::Default::Index
      input do
        datetime :from
        datetime :to

        patch :limit, default: 25, fill: true
      end

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def query
        node = ::Node.find(params[:node_id])
        q = node.node_statuses
        q = q.where('created_at >= ?', input[:from]) if input[:from]
        q = q.where('created_at <= ?', input[:to]) if input[:to]
        q
      end

      def count
        query.count
      end

      def exec
        query.order('created_at DESC').offset(input[:offset]).limit(input[:limit])
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      output do
        use :all
      end
      
      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        node = ::Node.find(params[:node_id])
        node.node_statuses.find(params[:status_id])
      end
    end
  end
end
