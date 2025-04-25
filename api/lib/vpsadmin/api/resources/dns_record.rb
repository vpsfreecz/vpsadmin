module VpsAdmin::API::Resources
  class DnsRecord < HaveAPI::Resource
    model ::DnsRecord
    desc 'Manage DNS records'

    params(:common) do
      resource DnsZone, value_label: :name
      string :name, desc: 'Domain name, @ as alias to origin, * for wildcards'
      string :type, db_name: :record_type
      string :content
      integer :ttl, label: 'TTL', desc: 'Optional TTL in seconds, defaults to zone TTL'
      integer :priority, label: 'Priority', desc: 'Optional priority, used for MX and SRV records'
      text :comment, desc: 'Optional comment'
      bool :enabled, default: true
      bool :dynamic_update_enabled, label: 'Enable dynamic update', desc: 'Only for A and AAAA records', default: false
    end

    params(:all) do
      integer :id, label: 'ID'
      use :common
      bool :managed
      string :dynamic_update_url, label: 'Dynamic update URL'
      datetime :created_at
      datetime :updated_at
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List DNS records'

      input do
        use :common, include: %i[dns_zone]
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
        q = self.class.model.joins(:dns_zone).existing.where(with_restricted)
        q = q.where(dns_zone: input[:dns_zone]) if input[:dns_zone]
        q
      end

      def count
        query.count
      end

      def exec
        with_includes(query).order('dns_zone_id, record_type, name, priority')
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show DNS record'

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict dns_zones: { user_id: u.id }
        allow
      end

      def prepare
        @record = self.class.model.joins(:dns_zone).existing.find_by(with_restricted(id: params[:dns_record_id]))
      end

      def exec
        @record
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      desc 'Create a DNS record'
      blocking true

      input do
        use :common

        %i[dns_zone type content].each do |v|
          patch v, required: true
        end
      end

      output do
        use :all
      end

      authorize do
        allow
      end

      include VpsAdmin::API::Lifetimes::ActionHelpers

      def exec
        if current_user.role != :admin && input[:dns_zone].user != current_user
          error!('access to the zone denied')
        end

        object_state_check!(input[:dns_zone].user) if input[:dns_zone].user_id

        @chain, ret = VpsAdmin::API::Operations::DnsZone::CreateRecord.run(to_db_names(input))
        ret
      rescue ActiveRecord::RecordInvalid => e
        error!('create failed', e.record.errors.to_hash)
      rescue VpsAdmin::API::Exceptions::OperationError => e
        error!(e.message)
      end

      def state_id
        @chain && @chain.id
      end
    end

    class Update < HaveAPI::Actions::Default::Update
      desc 'Update DNS record'
      blocking true

      input do
        use :common, include: %i[content ttl priority comment dynamic_update_enabled enabled]
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
        record = self.class.model.joins(:dns_zone).existing.find_by!(with_restricted(id: params[:dns_record_id]))
        object_state_check!(record.dns_zone.user) if record.dns_zone.user_id

        @chain, ret = VpsAdmin::API::Operations::DnsZone::UpdateRecord.run(record, to_db_names(input))
        ret
      rescue ActiveRecord::RecordInvalid => e
        error!('update failed', e.record.errors.to_hash)
      rescue VpsAdmin::API::Exceptions::OperationError => e
        error!(e.message)
      end

      def state_id
        @chain && @chain.id
      end
    end

    class Delete < HaveAPI::Actions::Default::Delete
      desc 'Delete DNS record'
      blocking true

      authorize do |u|
        allow if u.role == :admin
        restrict dns_zones: { user_id: u.id }
        allow
      end

      include VpsAdmin::API::Lifetimes::ActionHelpers

      def exec
        record = self.class.model.joins(:dns_zone).existing.find_by!(with_restricted(id: params[:dns_record_id]))

        object_state_check!(record.dns_zone.user) if record.dns_zone.user_id

        @chain = VpsAdmin::API::Operations::DnsZone::DestroyRecord.run(record)
        ok!
      rescue VpsAdmin::API::Exceptions::OperationError => e
        error!(e.message)
      end

      def state_id
        @chain && @chain.id
      end
    end

    class DynamicUpdate < HaveAPI::Action
      desc "Update DNS record with the client's address"
      http_method :get
      route 'dynamic_update/{access_token}'
      auth false
      blocking true

      output do
        use :all, include: %i[content]
      end

      authorize { allow }

      include VpsAdmin::API::Lifetimes::ActionHelpers

      def exec
        @chain, ret = VpsAdmin::API::Operations::DnsZone::DynamicUpdate.run(request, params[:access_token]) do |record|
          object_state_check!(record.dns_zone.user) if record.dns_zone.user_id
        end

        ret
      rescue VpsAdmin::API::Exceptions::OperationError => e
        error!(e.message)
      end

      def state_id
        @chain && @chain.id
      end
    end
  end
end
