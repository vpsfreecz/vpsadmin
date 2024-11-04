module VpsAdmin::API::Resources
  class NetworkInterfaceMonitor < HaveAPI::Resource
    desc 'View current network interface traffic'
    model ::NetworkInterfaceMonitor

    params(:all) do
      id :id
      resource VpsAdmin::API::Resources::NetworkInterface, value_label: :name
      integer :bytes
      integer :bytes_in
      integer :bytes_out
      integer :packets
      integer :packets_in
      integer :packets_out
      integer :delta
      datetime :updated_at
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List current network interface traffic'

      input do
        resource VpsAdmin::API::Resources::User, value_label: :login
        resource VpsAdmin::API::Resources::Environment
        resource VpsAdmin::API::Resources::Location
        resource VpsAdmin::API::Resources::Node, value_label: :domain_name
        resource VpsAdmin::API::Resources::VPS, value_label: :hostname
        resource VpsAdmin::API::Resources::NetworkInterface, value_label: :name

        string :order, default: '-bytes', fill: true

        patch :limit, default: 25, fill: true
      end

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        input blacklist: %i[user]
        allow
      end

      def query
        q = ::NetworkInterfaceMonitor.joins(:network_interface).where.not(
          network_interfaces: { id: nil }
        )

        if current_user.role != :admin
          q = q.joins(network_interface: :vps).where(
            vpses: { user_id: current_user.id }
          )
        end

        if input[:user]
          q = q.joins(network_interface: :vps).where(
            vpses: { user_id: input[:user].id }
          )
        end

        if input[:environment]
          q = q.joins(network_interface: { vps: { node: :location } }).where(
            locations: { environment_id: input[:environment].id }
          )
        end

        if input[:location]
          q = q.joins(network_interface: { vps: :node }).where(
            nodes: { location_id: input[:location].id }
          )
        end

        if input[:node]
          q = q.joins(network_interface: :vps).where(
            vpses: { node_id: input[:node].id }
          )
        end

        if input[:vps]
          q = q.joins(:network_interface).where(
            network_interfaces: { vps_id: input[:vps].id }
          )
        end

        q = q.where(id: input[:network_interface].id) if input[:network_interface]

        q
      end

      def count
        query.count
      end

      def exec
        q = with_includes(query).offset(input[:offset]).limit(input[:limit])
        apply_order(q, input[:order])
      end

      protected

      def apply_order(q, order_by)
        if order_by.start_with?('-')
          desc = true
          order_by = order_by[1..]
        end

        sym = order_by.to_sym

        param = self.class.output.params.detect do |p|
          p.name == sym
        end

        error!('invalid order') if param.nil?

        q.order(Arel.sql("#{order_by} #{desc ? 'DESC' : 'ASC'}"))
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show current network interface traffic'

      output do
        use :all
      end

      authorize do |_u|
        allow
      end

      def prepare
        q = ::NetworkInterface

        q = q.joins(network_interface: :vps).where(vpses: { user_id: current_user.id }) if current_user.role != :admin

        @mon = q.find_by!(id: params[:network_interface_monitor_id])
      end

      def exec
        @mon
      end
    end
  end
end
