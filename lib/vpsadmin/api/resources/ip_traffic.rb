module VpsAdmin::API::Resources
  class IpTraffic < HaveAPI::Resource
    desc 'Browse IP traffic records'
    model ::IpTrafficMonthlySummary

    params(:filters) do
      resource VpsAdmin::API::Resources::IpAddress, value_label: :addr
      resource VpsAdmin::API::Resources::User, value_label: :login
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
        resource VpsAdmin::API::Resources::Environment
        resource VpsAdmin::API::Resources::Location
        resource VpsAdmin::API::Resources::Network
        resource VpsAdmin::API::Resources::IpRange
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
        q = ::IpTrafficMonthlySummary.where(with_restricted)

        # Directly accessible filters
        %i(ip_address user year month).each do |f|
          q = q.where(f => input[f]) if input.has_key?(f)
        end

        # Custom filters
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
              vps_ip: {network_id: input[:network].id}
          )
        end

        if input[:ip_range]
          q = q.joins(:ip_address).where(
              vps_ip: {network_id: input[:ip_range].id}
          )
        end

        if input[:node]
          q = q.joins(ip_address: :vps).where(
              vps: {vps_server: input[:node].id}
          )
        end

        if input.has_key?(:vps)
          q = q.joins(:ip_address).where(
              vps_ip: {vps_id: input[:vps] && input[:vps].id}
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
          q = q.order('(bytes_in + bytes_out) DESC')
        
        when 'ascending'
          q = q.order('(bytes_in + bytes_out) ASC')

        else
          error('invalid order')
        end

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
  
    class UserTop < HaveAPI::Actions::Default::Index
      desc "Summed users' traffic"
      route ':%{resource}_id/user_top'
      http_method :get
      aliases []
      
      input do
        resource VpsAdmin::API::Resources::Environment
        resource VpsAdmin::API::Resources::Location
        resource VpsAdmin::API::Resources::Network
        resource VpsAdmin::API::Resources::Node
        integer :year
        integer :month
        datetime :from
        datetime :to
        string :accumulate, choices: %w(monthly), required: true
        string :order, choices: %w(created_at descending ascending), default: 'created_at'

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
            ip_traffic_monthly_summaries.user_id, ip_traffic_monthly_summaries.created_at,
            SUM(packets_in) AS sum_packets_in, SUM(packets_out) AS sum_packets_out,
            SUM(bytes_in) AS sum_bytes_in, SUM(bytes_out) AS sum_bytes_out
        ').joins(:user).group('members.m_id, ip_traffic_monthly_summaries.created_at')
        
        # Directly accessible filters
        %i(year month).each do |f|
          q = q.where(f => input[f]) if input.has_key?(f)
        end

        # Custom filters
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
              vps_ip: {network_id: input[:network].id}
          )
        end

        if input[:node]
          q = q.joins(ip_address: :vps).where(
              vps: {vps_server: input[:node].id}
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
  end
end
