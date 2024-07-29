module VpsAdmin::API::Resources
  class DnsServerZone < HaveAPI::Resource
    model ::DnsServerZone
    desc 'Manage authoritative DNS zones on servers'

    params(:common) do
      resource DnsServer, value_label: :name
      resource DnsZone, value_label: :name
      string :type, db_name: :zone_type, choices: ::DnsServerZone.zone_types.keys.map(&:to_s)
    end

    params(:all) do
      integer :id, label: 'ID'
      use :common
      integer :serial
      datetime :loaded_at
      datetime :expires_at
      datetime :refresh_at
      datetime :last_check_at
      datetime :created_at
      datetime :updated_at
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List DNS zones on servers'

      input do
        use :common
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

        %w[dns_server dns_zone].each do |v|
          q = q.where(v => input[v]) if input[v]
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
      desc 'Show DNS zone on server'

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict dns_zones: { user_id: u.id }
        allow
      end

      def prepare
        @server_zone = with_includes(self.class.model.existing.joins(:dns_zone).where(with_restricted(id: params[:dns_server_zone_id]))).take!
      end

      def exec
        @server_zone
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      desc 'Add DNS zone to a server'
      blocking true

      input do
        use :common
        patch :dns_zone, required: true
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        @chain, ret = VpsAdmin::API::Operations::DnsServerZone::Create.run(to_db_names(input))
        ret
      rescue ActiveRecord::RecordInvalid => e
        error('create failed', e.record.errors.to_hash)
      rescue ActiveRecord::RecordNotUnique => e
        error("zone #{input[:dns_zone].name} already is on server #{input[:dns_server].name}")
      end

      def state_id
        @chain.id
      end
    end

    class Delete < HaveAPI::Actions::Default::Delete
      desc 'Delete DNS zone from server'
      blocking true

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        dns_server_zone = self.class.model.existing.find(params[:dns_server_zone_id])
        @chain = VpsAdmin::API::Operations::DnsServerZone::Destroy.run(dns_server_zone)
        ok
      end

      def state_id
        @chain.id
      end
    end
  end
end
