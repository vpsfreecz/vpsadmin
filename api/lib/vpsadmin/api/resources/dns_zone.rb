module VpsAdmin::API::Resources
  class DnsZone < HaveAPI::Resource
    model ::DnsZone
    desc 'Manage DNS zones'

    params(:common) do
      string :name
      resource User, value_label: :login
      string :reverse_network_address
      string :reverse_network_prefix
      string :label
      string :role, db_name: :zone_role, choices: ::DnsZone.zone_roles.keys.map(&:to_s)
      string :source, db_name: :zone_source, choices: ::DnsZone.zone_sources.keys.map(&:to_s)
      integer :default_ttl
      string :email
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

      input do
        use :common, include: %i[user role source enabled]
      end

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id
        input whitelist: %i[role source enabled]
        allow
      end

      def query
        q = self.class.model.existing.where(with_restricted)
        db_input = to_db_names(input)

        %i[user zone_role zone_source enabled].each do |v|
          q = q.where(v => db_input[v]) if db_input.has_key?(v)
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
      desc 'Show DNS zone'

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin

        restrict user_id: u.id
        allow
      end

      def prepare
        @zone = self.class.model.existing.find_by!(with_restricted(id: params[:dns_zone_id]))
      end

      def exec
        @zone
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      desc 'Create a DNS zone'
      blocking true

      input do
        use :common
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        input whitelist: %i[name label source email enabled]
        allow
      end

      def exec
        op =
          if current_user.role != :admin || input[:user]
            VpsAdmin::API::Operations::DnsZone::CreateUser
          else
            VpsAdmin::API::Operations::DnsZone::CreateSystem
          end

        @chain, ret = op.run(to_db_names(input))
        ret
      rescue ActiveRecord::RecordInvalid => e
        error('create failed', e.record.errors.to_hash)
      rescue ActiveRecord::RecordNotUnique => e
        error('zone with this name already exists')
      end

      def state_id
        @chain && @chain.id
      end
    end

    class Update < HaveAPI::Actions::Default::Update
      desc 'Update DNS zone'
      blocking true

      input do
        use :common, include: %i[label default_ttl email enabled]
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id
        allow
      end

      def exec
        @chain, ret = VpsAdmin::API::Operations::DnsZone::Update.run(
          self.class.model.existing.find_by!(with_restricted(id: params[:dns_zone_id])),
          to_db_names(input)
        )
        ret
      rescue ActiveRecord::RecordInvalid => e
        error('update failed', e.record.errors.to_hash)
      end

      def state_id
        @chain && @chain.id
      end
    end

    class Delete < HaveAPI::Actions::Default::Delete
      desc 'Delete DNS zone'
      blocking true

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id
        allow
      end

      def exec
        zone = self.class.model.existing.find_by!(with_restricted(id: params[:dns_zone_id]))

        op =
          if current_user.role != :admin || zone.user_id
            VpsAdmin::API::Operations::DnsZone::DestroyUser
          else
            VpsAdmin::API::Operations::DnsZone::DestroySystem
          end

        @chain = op.run(zone)
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
