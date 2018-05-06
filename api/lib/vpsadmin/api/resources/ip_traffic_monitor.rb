module VpsAdmin::API::Resources
  class IpTrafficMonitor < HaveAPI::Resource
    desc 'View current IP traffic'
    model ::IpTrafficLiveMonitor

    params(:filters) do
      resource VpsAdmin::API::Resources::IpAddress, value_label: :addr
      resource VpsAdmin::API::Resources::User, value_label: :login
    end

    params(:all) do
      fields = Proc.new do |*name|
        %i(packets bytes).each do |stat|
          integer :"#{(name + [stat]).join('_')}"

          %i(in out).each do |dir|
            integer :"#{(name + [stat, dir]).join('_')}"
          end
        end
      end

      id :id
      use :filters

      fields.call

      %i(public private).each do |role|
        fields.call(role)

        %i(tcp udp other).each do |proto|
          fields.call(role, proto)
        end
      end

      datetime :updated_at
      integer :delta
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List current IP traffic'

      input do
        use :filters
        integer :ip_version, choices: [4, 6]
        resource VpsAdmin::API::Resources::Environment
        resource VpsAdmin::API::Resources::Location
        resource VpsAdmin::API::Resources::Network
        resource VpsAdmin::API::Resources::Node
        resource VpsAdmin::API::Resources::VPS

        string :order, default: '-bytes', fill: true

        patch :limit, default: 25, fill: true
      end

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        input blacklist: %i(user)
        allow
      end

      def query
        q = ::IpTrafficLiveMonitor.where('delta > 0')

        if current_user.role != :admin
          q = q.joins(ip_address: :vps).where(vpses: {user_id: current_user.id})
        end

        # Directly accessible filters
        %i(ip_address).each do |f|
          q = q.where(f => input[f]) if input.has_key?(f)
        end

        # Custom filters
        if input[:ip_version]
          q = q.joins(ip_address: :network).where(
            networks: {ip_version: input[:ip_version]}
          )
        end

        if input[:environment]
          q = q.joins(ip_address: {network: :location}).where(
            locations: {environment_id: input[:environment].id}
          )
        end

        if input[:location]
          q = q.joins(ip_address: :network).where(
            networks: {location_id: input[:location].id}
          )
        end

        if input[:network]
          q = q.joins(:ip_address).where(
            ip_addresses: {network_id: input[:network].id}
          )
        end

        if input[:node]
          q = q.joins(ip_address: :vps).where(
            vpses: {node_id: input[:node].id}
          )
        end

        if input.has_key?(:vps)
          q = q.joins(:ip_address).where(
            ip_addresses: {vps_id: input[:vps] && input[:vps].id}
          )
        end

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
          order_by = order_by[1..-1]
        end

        sym = order_by.to_sym

        param = self.class.output.params.detect do |p|
          p.name == sym
        end

        if param.nil? || %w(packets bytes).detect { |v| order_by.include?(v) }.nil?
          error('invalid order')
        end

        q.order("#{order_by} #{desc ? 'DESC' : 'ASC'}")
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show an IP traffic monitor'

      output do
        use :all
      end

      authorize do |u|
        allow
      end

      def prepare
        q = ::IpTrafficLiveMonitor

        if current_user.role != :admin
          q = q.joins(ip_address: :vps).where(vpses: {user_id: current_user.id})
        end

        @mon = q.find_by!(id: params[:ip_traffic_monitor_id])
      end

      def exec
        @mon
      end
    end
  end
end
