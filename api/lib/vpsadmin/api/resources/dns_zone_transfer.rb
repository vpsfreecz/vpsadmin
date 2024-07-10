module VpsAdmin::API::Resources
  class DnsZoneTransfer < HaveAPI::Resource
    model ::DnsZoneTransfer
    desc 'Manage DNS zone transfers'

    params(:common) do
      resource DnsZone
      resource HostIpAddress, value_label: :addr
      string :peer_type, db_name: :peer_type, choices: ::DnsZoneTransfer.peer_types.keys.map(&:to_s)
      bool :enabled
    end

    params(:all) do
      integer :id, label: 'ID'
      use :common
      datetime :created_at
      datetime :updated_at
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List DNS zone transfers'

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def query
        self.class.model.all
      end

      def count
        query.count
      end

      def exec
        query.limit(input[:limit]).offset(input[:offset])
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show DNS zone transfer'

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def prepare
        @zone = self.class.model.find(params[:dns_zone_transfer_id])
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
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        @chain, ret = VpsAdmin::API::Operations::DnsZoneTransfer::Create.run(to_db_names(input))
        ret
      rescue ActiveRecord::RecordInvalid => e
        error('create failed', e.record.errors.to_hash)
      rescue ActiveRecord::RecordNotUnique => e
        error("transfer between zone #{input[:dns_zone].name} and host IP #{input[:host_ip_address].ip_addr} already exists")
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
      end

      def exec
        @chain, = VpsAdmin::API::Operations::DnsZoneTransfer::Destroy.run(self.class.model.find(params[:dns_zone_transfer_id]))
        ok
      rescue VpsAdmin::API::Exceptions::OperationError => e
        error(e.message)
      end

      def state_id
        @chain && @chain.id
      end
    end
  end
end
