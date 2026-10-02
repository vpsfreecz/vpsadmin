module VpsAdmin::API::Resources
  class IpAddressAssignment < HaveAPI::Resource
    model ::IpAddressAssignment
    desc 'Browse IP address assignments'

    params(:all) do
      integer :id, label: 'ID'
      resource IpAddress, value_label: :addr
      string :ip_addr
      integer :ip_prefix
      resource User, value_label: :login
      integer :raw_user_id
      resource VPS, value_label: :hostname
      integer :raw_vps_id
      datetime :from_date
      datetime :to_date
      resource TransactionChain, name: :assigned_by_chain, value_label: :name, nullable: true
      resource TransactionChain, name: :unassigned_by_chain, value_label: :name, nullable: true
      bool :reconstructed
      datetime :created_at
      datetime :updated_at
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List IP address assignments'

      input do
        patch :from_id,
              desc: 'Continue after the last assignment from the previous page. Keep the same filters and order. ' \
                    'Assignments are ordered by from_date and ID in the selected direction. ' \
                    'An unavailable or differently scoped cursor returns HTTP 400.'
        use :all, include: %i[
          ip_address
          ip_addr
          ip_prefix
          ip_version
          user
          vps
          assigned_by_chain
          unassigned_by_chain
          reconstructed
        ]

        resource Location
        resource Network, value_label: :address
        integer :ip_version, choices: [4, 6]
        string :order, choices: %w[newest oldest], default: 'newest', fill: true
        bool :active
      end

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id
        input blacklist: %i[user]
        output blacklist: %i[user raw_user_id]
        allow
      end

      def query
        q = ::IpAddressAssignment.where(with_restricted)

        %i[
          ip_address
          ip_addr
          ip_prefix
          user
          vps
          assigned_by_chain
          unassigned_by_chain
          reconstructed
        ].each do |v|
          q = q.where(v => input[v]) if input.has_key?(v)
        end

        if input[:location]
          locs = ::LocationNetwork.where(
            location: input[:location]
          ).pluck(:network_id)

          q = q.joins(:ip_address).where(
            ip_addresses: { network_id: locs }
          )
        end

        if input[:network]
          q = q.joins(:ip_address).where(
            ip_addresses: { network_id: input[:network].id }
          )
        end

        if input[:ip_version]
          q = q.joins(ip_address: :network).where(
            networks: { ip_version: input[:ip_version] }
          )
        end

        if input[:active] === true
          q = q.where(to_date: nil)
        elsif input[:active] === false
          q = q.where.not(to_date: nil)
        end

        q
      end

      def count
        query.count
      end

      def exec
        q = query
        ascending = input[:order] == 'oldest'
        comparison = ascending ? '>' : '<'
        direction = ascending ? 'ASC' : 'DESC'

        q = ar_with_pagination(q, check: true) do |scope, from_id|
          cursor_date = q.where(id: from_id).pick(:from_date)
          error!('Invalid pagination cursor', {}, http_status: 400) unless cursor_date

          scope.where(
            "ip_address_assignments.from_date #{comparison} ? OR " \
            "(ip_address_assignments.from_date = ? AND ip_address_assignments.id #{comparison} ?)",
            cursor_date, cursor_date, from_id
          )
        end

        q.order("ip_address_assignments.from_date #{direction}, ip_address_assignments.id #{direction}")
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show IP address assignment'

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id
        output blacklist: %i[user raw_user_id]
        allow
      end

      def prepare
        @assignment = ::IpAddressAssignment.find_by(with_restricted(
                                                      id: path_params['ip_address_assignment_id']
                                                    ))
      end

      def exec
        @assignment
      end
    end
  end
end
