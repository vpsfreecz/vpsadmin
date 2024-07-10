module VpsAdmin::API::Resources
  class DnsZone < HaveAPI::Resource
    model ::DnsZone
    desc 'Manage DNS zones'

    params(:common) do
      string :name
      string :reverse_network_address
      string :reverse_network_prefix
      string :label
      string :role, db_name: :zone_role, choices: ::DnsZone.zone_roles.keys.map(&:to_s)
      string :source, db_name: :zone_source, choices: ::DnsZone.zone_sources.keys.map(&:to_s)
      integer :default_ttl
      string :email
      string :tsig_algorithm, default: 'hmac-256'
      string :tsig_key
      bool :enabled
    end

    params(:all) do
      integer :id, label: 'ID'
      use :common
      integer :serial
      datetime :created_at
      datetime :updated_at
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List DNS zones'

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
      desc 'Show DNS zone'

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def prepare
        @zone = self.class.model.find(params[:dns_zone_id])
      end

      def exec
        @zone
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      desc 'Create a DNS zone'

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
        VpsAdmin::API::Operations::DnsZone::Create.run(to_db_names(input))
      rescue ActiveRecord::RecordInvalid => e
        error('create failed', e.record.errors.to_hash)
      rescue ActiveRecord::RecordNotUnique => e
        error('zone with this name already exists')
      end
    end

    class Update < HaveAPI::Actions::Default::Update
      desc 'Update DNS zone'
      blocking true

      input do
        use :common, include: %i[label default_ttl email tsig_algorithm tsig_key enabled]
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        @chain, ret = VpsAdmin::API::Operations::DnsZone::Update.run(
          self.class.model.find(params[:dns_zone_id]),
          to_db_names(input)
        )
        ret
      end

      def state_id
        @chain && @chain.id
      end
    end

    class Delete < HaveAPI::Actions::Default::Delete
      desc 'Delete DNS zone'

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        VpsAdmin::API::Operations::DnsZone::Destroy.run(self.class.model.find(params[:dns_zone_id]))
        ok
      rescue VpsAdmin::API::Exceptions::OperationError => e
        error(e.message)
      end
    end
  end
end
