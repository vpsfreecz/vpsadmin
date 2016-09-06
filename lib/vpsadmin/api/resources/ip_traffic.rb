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
        resource VpsAdmin::API::Resources::VPS
        integer :year
        integer :month
        datetime :since
        string :accumulate, choices: %w(monthly), required: true
        string :order, choices: %w(created_at descending ascending), default: 'created_at'

        patch :limit, default: 25
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

        %i(ip_address user year month).each do |f|
          q = q.where(f => input[f]) if input.has_key?(f)
        end

        if input.has_key?(:vps)
          q = q.joins(:ip_address).where(
              vps_ip: {vps_id: input[:vps] && input[:vps].id}
          )
        end

        q = q.where('created_at > ?', input[:since]) if input[:since]
        q
      end

      def count
        query.count
      end

      def exec
        q = with_includes(query).offset(input[:offset]).limit(input[:limit])

        case input[:order]
        when nil, 'created_at'
          q = q.order('created_at')
        
        when 'descending'
          q = q.order('(bytes_in + bytes_out) DESC')
        
        when 'ascending'
          q = q.order('(bytes_in + bytes_out) ASC')

        else
          puts "\n\nDAT ERROR\n\n"
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
  end
end
