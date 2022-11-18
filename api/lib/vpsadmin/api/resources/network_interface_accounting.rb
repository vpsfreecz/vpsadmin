module VpsAdmin::API::Resources
  class NetworkInterfaceAccounting < HaveAPI::Resource
    desc 'Network interface accounting'
    model ::NetworkInterfaceMonthlyAccounting

    params(:all) do
      id :id
      resource VpsAdmin::API::Resources::NetworkInterface, value_label: :name
      integer :bytes_in
      integer :bytes_out
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
        string :order, choices: %w(created_at updated_at descending ascending),
          default: 'created_at'

        patch :limit, default: 25, fill: true
      end

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        input blacklist: %i(user)
        output blacklist: %i(user)
        restrict vpses: {user_id: u.id}
        allow
      end

      def query
        klass = self.class.model
        table = klass.table_name
        q = klass.joins(network_interface: :vps).where(with_restricted)

        # Directly accessible filters
        %i(year month).each do |f|
          q = q.where(f => input[f]) if input.has_key?(f)
        end

        # Custom filters
        if input[:user]
          q = q.where(vpses: {user_id: input[:user].id})
        end

        if input[:environment]
          q = q.joins(network_interface: {vps: {node: :location}}).where(
            locations: {environment_id: input[:environment].id}
          )
        end

        if input[:location]
          q = q.joins(network_interface: {vps: :node}).where(
            nodes: {location_id: input[:location].id}
          )
        end

        if input[:node]
          q = q.joins(network_interface: :vps).where(
            vpses: {node_id: input[:node].id}
          )
        end

        if input[:vps]
          q = q.joins(:network_interface).where(
            network_interfaces: {vps_id: input[:vps].id}
          )
        end

        if input[:from]
          q = q.where("#{table}.created_at >= ?", input[:from])
        end

        if input[:to]
          q = q.where("#{table}.created_at <= ?", input[:to])
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

        when 'updated_at'
          q = q.order('updated_at DESC')

        when 'descending'
          q = q.order(Arel.sql('(bytes_in + bytes_out) DESC'))

        when 'ascending'
          q = q.order(Arel.sql('(bytes_in + bytes_out) ASC'))

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
        resource VpsAdmin::API::Resources::Environment
        resource VpsAdmin::API::Resources::Location
        resource VpsAdmin::API::Resources::Node
        integer :year
        integer :month
        datetime :from
        datetime :to

        patch :limit, default: 25, fill: true
      end

      output(:object_list) do
        resource VpsAdmin::API::Resources::User, value_label: :login
        integer :bytes_in, db_name: :sum_bytes_in
        integer :bytes_out, db_name: :sum_bytes_out
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
            #{table}.id, #{table}.year, #{table}.month,
            #{table}.network_interface_id, vpses.user_id,
            SUM(bytes_in) AS sum_bytes_in, SUM(bytes_out) AS sum_bytes_out,
            SUM(packets_in) AS sum_packets_in, SUM(packets_out) AS sum_packets_out
          ")
          .joins(network_interface: :vps)
          .group("vpses.user_id, #{table}.year, #{table}.month")

        # Directly accessible filters
        %i(year month).each do |f|
          q = q.where(f => input[f]) if input.has_key?(f)
        end

        # Custom filters
        if input[:environment]
          q = q.joins(network_interface: {vps: {node: :location}}).where(
            locations: {environment_id: input[:environment].id}
          )
        end

        if input[:location]
          q = q.joins(network_interface: {vps: :node}).where(
            nodes: {location_id: input[:location].id}
          )
        end

        if input[:node]
          q = q.joins(network_interface: :vps).where(
            vpses: {node_id: input[:node].id}
          )
        end

        if input[:from]
          q = q.where("#{table}.created_at >= ?", input[:from])
        end

        if input[:to]
          q = q.where("#{table}.created_at <= ?", input[:to])
        end

        q
      end

      def count
        query.count
      end

      def exec
        q = query.offset(input[:offset]).limit(input[:limit])
        q = q.order(Arel.sql('(SUM(bytes_in) + SUM(bytes_out)) DESC'))
        q
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show network accounting record'

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        output blacklist: %i(user)
        restrict vpses: {user_id: u.id}
        allow
      end

      def prepare
        @accounting = self.class.model
          .joins(network_interface: :vps)
          .find_by!(with_restricted(
            id: params[:network_interface_accounting_id]
          ))
      end

      def exec
        @accounting
      end
    end
  end
end
