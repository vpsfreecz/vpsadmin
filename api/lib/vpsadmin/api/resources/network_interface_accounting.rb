module VpsAdmin::API::Resources
  class NetworkInterfaceAccounting < HaveAPI::Resource
    desc 'Network interface accounting'
    model ::NetworkInterfaceMonthlyAccounting

    params(:all) do
      resource VpsAdmin::API::Resources::NetworkInterface, value_label: :name
      integer :bytes
      integer :bytes_in
      integer :bytes_out
      integer :packets
      integer :packets_in
      integer :packets_out
      integer :year
      integer :month
      datetime :created_at
      datetime :updated_at
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List network interface accounting'

      input do
        resource VpsAdmin::API::Resources::User, value_label: :login
        resource VpsAdmin::API::Resources::Environment
        resource VpsAdmin::API::Resources::Location
        resource VpsAdmin::API::Resources::Node, value_label: :domain_name
        resource VpsAdmin::API::Resources::VPS, value_label: :hostname
        integer :year
        integer :month
        datetime :from
        datetime :to
        string :order, choices: %w[created_at updated_at descending ascending],
                       default: 'created_at'

        patch :limit, default: 25, fill: true
        remove :from_id # default pagination by from_id is not used
        integer :from_bytes, desc: 'Paginate by in/out bytes'
        datetime :from_date, desc: 'Paginate by create/update date'
      end

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        input blacklist: %i[user]
        output blacklist: %i[user]
        restrict vpses: { user_id: u.id }
        allow
      end

      def query
        klass = self.class.model
        table = klass.table_name
        q = klass.joins(network_interface: :vps).where(with_restricted)

        # Directly accessible filters
        %i[year month].each do |f|
          q = q.where(f => input[f]) if input.has_key?(f)
        end

        # Custom filters
        q = q.where(vpses: { user_id: input[:user].id }) if input[:user]

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

        q = q.where("#{table}.created_at >= ?", input[:from]) if input[:from]

        q = q.where("#{table}.created_at <= ?", input[:to]) if input[:to]

        q
      end

      def count
        query.count
      end

      def exec
        q = with_includes(query)
        table = self.class.model.table_name

        case input[:order]
        when nil, 'created_at'
          ar_with_pagination(q, parameter: :from_date) do |q2, from_date|
            q2.where("`#{table}`.`created_at` < ?", from_date)
          end.order('created_at DESC')

        when 'updated_at'
          ar_with_pagination(q, parameter: :from_date) do |q2, from_date|
            q2.where("`#{table}`.`updated_at` < ?", from_date)
          end.order('updated_at DESC')

        when 'descending'
          ar_with_pagination(q, parameter: :from_bytes) do |q2, from_bytes|
            q2.where("`#{table}`.`bytes_in` + `#{table}`.`bytes_out` < ?", from_bytes)
          end.order(Arel.sql('(bytes_in + bytes_out) DESC'))

        when 'ascending'
          ar_with_pagination(q, parameter: :from_bytes) do |q2, from_bytes|
            q2.where("`#{table}`.`bytes_in` + `#{table}`.`bytes_out` > ?", from_bytes)
          end.order(Arel.sql('(bytes_in + bytes_out) ASC'))

        else
          error!('invalid order')
        end
      end
    end

    class UserTop < HaveAPI::Actions::Default::Index
      desc "Summed users' traffic"
      route 'user_top'
      http_method :get
      aliases []

      input do
        resource VpsAdmin::API::Resources::Environment
        resource VpsAdmin::API::Resources::Location
        resource VpsAdmin::API::Resources::Node
        integer :year
        integer :month
        datetime :from
        datetime :to

        patch :limit, default: 25, fill: true
        remove :from_id # default pagination by from_id is not used
        integer :from_bytes, desc: 'Paginate by in/out bytes'
      end

      output(:object_list) do
        resource VpsAdmin::API::Resources::User, value_label: :login
        integer :bytes, db_name: :sum_bytes
        integer :bytes_in, db_name: :sum_bytes_in
        integer :bytes_out, db_name: :sum_bytes_out
        integer :packets, db_name: :sum_packets
        integer :packets_in, db_name: :sum_packets_in
        integer :packets_out, db_name: :sum_packets_out
        integer :year
        integer :month
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def query
        klass = self.class.model
        table = klass.table_name

        q = self.class.model
                .select("
            #{table}.year, #{table}.month,
            #{table}.network_interface_id, vpses.user_id,
            SUM(bytes_in) AS sum_bytes_in, SUM(bytes_out) AS sum_bytes_out,
            SUM(packets_in) AS sum_packets_in, SUM(packets_out) AS sum_packets_out
          ")
                .joins(network_interface: :vps)
                .group("vpses.user_id, #{table}.year, #{table}.month")

        # Directly accessible filters
        %i[year month].each do |f|
          q = q.where(f => input[f]) if input.has_key?(f)
        end

        # Custom filters
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

        q = q.where("#{table}.created_at >= ?", input[:from]) if input[:from]

        q = q.where("#{table}.created_at <= ?", input[:to]) if input[:to]

        q
      end

      def count
        query.count
      end

      def exec
        ar_with_pagination(query, parameter: :from_bytes) do |q, from_bytes|
          q.having('sum_bytes_in + sum_bytes_out < ?', from_bytes)
        end.order(Arel.sql('(SUM(bytes_in) + SUM(bytes_out)) DESC'))
      end
    end
  end
end
