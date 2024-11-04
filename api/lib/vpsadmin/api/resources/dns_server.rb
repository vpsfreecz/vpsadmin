module VpsAdmin::API::Resources
  class DnsServer < HaveAPI::Resource
    model ::DnsServer
    desc 'Manage authoritative DNS servers'

    params(:common) do
      resource Node, value_label: :domain_name
      string :name
      string :ipv4_addr
      string :ipv6_addr
      bool :hidden
      bool :enable_user_dns_zones
      string :user_dns_zone_type, choices: ::DnsServer.user_dns_zone_types.keys.map(&:to_s)
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
        restrict enable_user_dns_zones: true
        allow
      end

      def query
        self.class.model.where(with_restricted)
      end

      def count
        query.count
      end

      def exec
        with_pagination(with_includes(query))
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show authoritative DNS server'

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict enable_user_dns_zones: true
        allow
      end

      def prepare
        @server = with_includes(self.class.model.where(with_restricted(id: params[:dns_server_id]))).take!
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
        error!('create failed', e.record.errors.to_hash)
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
          error!('DNS server is in use, remove server zones first')
        end

        server.destroy!
        ok!
      end
    end
  end
end
