module VpsAdmin::API::Resources
  class IpTraffic < HaveAPI::Resource
    desc 'Browse IP traffic records'
    model ::IpTrafficMonthlySummary

    params(:filters) do
      resource VpsAdmin::API::Resources::IpAddress, value_label: :addr
      resource VpsAdmin::API::Resources::User, value_label: :login
      string :role, choices: %i(public private), db_name: :api_role
      string :protocol, choices: %w(all tcp udp other sum), db_name: :api_protocol
    end

    params(:all) do
      id :id
      use :filters
      integer :packets_in
      integer :packets_out
      integer :bytes_in
      integer :bytes_out
      datetime :created_at
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List IP traffic'

      input do
        use :filters
        integer :ip_version, choices: [4, 6]
        resource VpsAdmin::API::Resources::Environment
        resource VpsAdmin::API::Resources::Location
        resource VpsAdmin::API::Resources::Network
        resource VpsAdmin::API::Resources::Node
        resource VpsAdmin::API::Resources::VPS
        integer :year
        integer :month
        datetime :from
        datetime :to
        string :accumulate, choices: %w(monthly), required: true
        string :order, choices: %w(created_at descending ascending), default: 'created_at'

        patch :limit, default: 25, fill: true
      end

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        input blacklist: %i(user)
        output blacklist: %i(user)
        restrict user: u
        allow
      end

      def query
        table = ::IpTrafficMonthlySummary.table_name
        q = ::IpTrafficMonthlySummary.where(with_restricted)

        # Directly accessible filters
        %i(ip_address user year month).each do |f|
          q = q.where(f => input[f]) if input.has_key?(f)
        end

        # Custom filters
        if input[:role]
          q = q.where(role: ::IpTrafficMonthlySummary.roles["role_#{input[:role]}"])
        end

        if input[:ip_version]
          q = q.joins(ip_address: :network).where(
            networks: {ip_version: input[:ip_version]}
          )
        end

        case input[:protocol]
        when nil, 'all'
          # Do nothing

        when 'tcp', 'udp', 'other'
          q = q.where(
            protocol: ::IpTrafficMonthlySummary.protocols["proto_#{input[:protocol]}"]
          )

        when 'sum'
          q = q.select("
            #{table}.*,
            1 AS is_sum,
            SUM(packets_in) AS packets_in, SUM(packets_out) AS packets_out,
            SUM(bytes_in) AS bytes_in, SUM(bytes_out) AS bytes_out
          ").group("#{table}.ip_address_id, #{table}.role, #{table}.created_at")
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

        if input[:from]
          q = q.where('ip_traffic_monthly_summaries.created_at >= ?', input[:from])
        end

        if input[:to]
          q = q.where('ip_traffic_monthly_summaries.created_at <= ?', input[:to])
        end

        q
      end

      def count
        query.count
      end

      def exec
        q = with_includes(query).offset(input[:offset]).limit(input[:limit])

        case input[:order]
        when nil, 'created_at'
          q = q.order('created_at DESC')

        when 'descending'
          if input[:protocol] == 'sum'
            q = q.order('(SUM(bytes_in) + SUM(bytes_out)) DESC')

          else
            q = q.order('(bytes_in + bytes_out) DESC')
          end

        when 'ascending'
          if input[:protocol] == 'sum'
            q = q.order('(SUM(bytes_in) + SUM(bytes_out)) ASC')

          else
            q = q.order('(bytes_in + bytes_out) ASC')
          end

        else
          error('invalid order')
        end

        q
      end
    end

    class UserTop < HaveAPI::Actions::Default::Index
      desc "Summed users' traffic"
      route 'user_top'
      http_method :get
      aliases []

      input do
        string :role, choices: %i(public private), db_name: :api_role
        string :protocol, choices: %w(all tcp udp other), db_name: :api_protocol
        integer :ip_version, choices: [4, 6]
        resource VpsAdmin::API::Resources::Environment
        resource VpsAdmin::API::Resources::Location
        resource VpsAdmin::API::Resources::Network
        resource VpsAdmin::API::Resources::Node
        integer :year
        integer :month
        datetime :from
        datetime :to
        string :accumulate, choices: %w(monthly), required: true

        patch :limit, default: 25, fill: true
      end

      output(:object_list) do
        resource VpsAdmin::API::Resources::User, value_label: :login
        integer :packets_in, db_name: :sum_packets_in
        integer :packets_out, db_name: :sum_packets_out
        integer :bytes_in, db_name: :sum_bytes_in
        integer :bytes_out, db_name: :sum_bytes_out
        datetime :created_at
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def query
        q = ::IpTrafficMonthlySummary.select('
          ip_traffic_monthly_summaries.user_id,
          ip_traffic_monthly_summaries.role,
          ip_traffic_monthly_summaries.created_at,
          SUM(packets_in) AS sum_packets_in, SUM(packets_out) AS sum_packets_out,
          SUM(bytes_in) AS sum_bytes_in, SUM(bytes_out) AS sum_bytes_out
        ').joins(:user).group('users.id, ip_traffic_monthly_summaries.created_at')

        # Directly accessible filters
        %i(year month).each do |f|
          q = q.where(f => input[f]) if input.has_key?(f)
        end

        # Custom filters
        if input[:role]
          q = q.where(role: ::IpTrafficMonthlySummary.roles["role_#{input[:role]}"])
        end

        if input[:ip_version]
          q = q.joins(ip_address: :network).where(
              networks: {ip_version: input[:ip_version]}
          )
        end

        case input[:protocol]
        when nil, 'all'
          # Do nothing

        when 'tcp', 'udp', 'other'
          q = q.where(
            protocol: ::IpTrafficMonthlySummary.protocols["proto_#{input[:protocol]}"]
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

        if input[:from]
          q = q.where('ip_traffic_monthly_summaries.created_at >= ?', input[:from])
        end

        if input[:to]
          q = q.where('ip_traffic_monthly_summaries.created_at <= ?', input[:to])
        end

        q
      end

      def count
        query.count
      end

      def exec
        q = query.offset(input[:offset]).limit(input[:limit])
        q = q.order('(SUM(bytes_in) + SUM(bytes_out)) DESC')
        q
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show an IP traffic record'

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        output blacklist: %i(user)
        restrict user: u
        allow
      end

      def prepare
        @traffic = ::IpTrafficMonthlySummary.find_by!(with_restricted(
          id: params[:ip_traffic_id]
        ))
      end

      def exec
        @traffic
      end
    end
  end
end
