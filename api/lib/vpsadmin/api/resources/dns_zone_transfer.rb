module VpsAdmin::API::Resources
  class DnsZoneTransfer < HaveAPI::Resource
    model ::DnsZoneTransfer
    desc 'Manage DNS zone transfers'

    params(:common) do
      resource DnsZone
      resource HostIpAddress, value_label: :addr
      string :peer_type, db_name: :peer_type, choices: ::DnsZoneTransfer.peer_types.keys.map(&:to_s)
      resource DnsTsigKey, value_label: :name
    end

    params(:all) do
      integer :id, label: 'ID'
      use :common
      datetime :created_at
      datetime :updated_at
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List DNS zone transfers'

      input do
        use :common, include: %i[dns_zone host_ip_address peer_type dns_tsig_key]
      end

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict dns_zones: { user_id: u.id }
        allow
      end

      def query
        q = self.class.model.existing.joins(:dns_zone).where(with_restricted)

        %i[dns_zone host_ip_address peer_type dns_tsig_key].each do |v|
          q = q.where(v => input[v]) if input.has_key?(v)
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

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show DNS zone transfer'

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict dns_zones: { user_id: u.id }
        allow
      end

      def prepare
        @zone = self.class.model.existing.joins(:dns_zone).find_by!(with_restricted(id: params[:dns_zone_transfer_id]))
      end

      def exec
        @zone
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      desc 'Create a DNS zone transfer'
      blocking true

      input do
        use :common
        patch :host_ip_address, required: true
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict dns_zones: { user_id: u.id }
        allow
      end

      include VpsAdmin::API::Lifetimes::ActionHelpers

      def exec
        if current_user.role != :admin && input[:dns_zone].user != current_user
          error!('access denied')
        end

        object_state_check!(input[:dns_zone].user) if input[:dns_zone].user_id

        @chain, ret = VpsAdmin::API::Operations::DnsZoneTransfer::Create.run(to_db_names(input))
        ret
      rescue ActiveRecord::RecordInvalid => e
        error!('create failed', e.record.errors.to_hash)
      rescue ActiveRecord::RecordNotUnique => e
        error!("transfer between zone #{input[:dns_zone].name} and host IP #{input[:host_ip_address].ip_addr} already exists")
      end

      def state_id
        @chain && @chain.id
      end
    end

    class Delete < HaveAPI::Actions::Default::Delete
      desc 'Delete DNS zone transfer'
      blocking true

      authorize do |u|
        allow if u.role == :admin
        restrict dns_zones: { user_id: u.id }
        allow
      end

      include VpsAdmin::API::Lifetimes::ActionHelpers

      def exec
        transfer = self.class.model.existing.joins(:dns_zone).find_by!(with_restricted(id: params[:dns_zone_transfer_id]))

        object_state_check!(transfer.dns_zone.user) if transfer.dns_zone.user_id

        @chain, = VpsAdmin::API::Operations::DnsZoneTransfer::Destroy.run(transfer)
        ok!
      rescue VpsAdmin::API::Exceptions::OperationError => e
        error!(e.message)
      end

      def state_id
        @chain && @chain.id
      end
    end
  end
end
