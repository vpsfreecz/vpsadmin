module VpsAdmin::API::Resources
  class DnsServer < HaveAPI::Resource
    model ::DnsServer
    desc 'Manage authoritative DNS servers'

    params(:common) do
      resource Node, value_label: :domain_name
      string :name
      bool :enable_user_dns_zones
    end

    params(:all) do
      integer :id, label: 'ID'
      use :common
      datetime :created_at
      datetime :updated_at
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List authoritative DNS servers'

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
      desc 'Show authoritative DNS server'

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def prepare
        @server = self.class.model.find(params[:dns_server_id])
      end

      def exec
        @server
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      desc 'Create an authoritative DNS server'

      input do
        use :common
        patch :node, required: true
        patch :name, required: true
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        self.class.model.create!(input)
      rescue ActiveRecord::RecordInvalid => e
        error('create failed', e.record.errors.to_hash)
      end
    end

    class Update < HaveAPI::Actions::Default::Update
      desc 'Update authoritative DNS server'

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
        server = self.class.model.find(params[:dns_server_id])
        server.update!(input)
        server
      end
    end

    class Delete < HaveAPI::Actions::Default::Delete
      desc 'Delete authoritative DNS server'

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        server = self.class.model.find(params[:dns_server_id])

        if server.dns_server_zones.any?
          error('DNS server is in use, remove server zones first')
        end

        server.destroy!
        ok
      end
    end
  end
end
