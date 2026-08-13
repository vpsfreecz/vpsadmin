module VpsAdmin::API::Resources
  class DnsServer < HaveAPI::Resource
    model ::DnsServer
    desc 'Manage authoritative DNS servers'

    params(:common) do
      resource Node, value_label: :domain_name
      string :name
      string :ipv4_addr, nullable: true
      string :ipv6_addr, nullable: true
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
        restrict enable_user_dns_zones: true, hidden: false
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

      authorize do |_u|
        allow
      end

      def prepare
        scope = if current_user.role == :admin
                  self.class.model.where(id: path_params['dns_server_id'])

                else
                  conditions = if flags[:inner_assoc]
                                 { hidden: false }
                               else
                                 { enable_user_dns_zones: true, hidden: false }
                               end

                  self.class.model.where(conditions.merge(id: path_params['dns_server_id']))
                end

        @server = with_includes(scope).take

        error!('DNS server not found', {}, http_status: 404) unless @server
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
        server = self.class.model.find(path_params['dns_server_id'])
        server.with_lock(requires_new: true) do
          server.update!(input)
          if server.saved_change_to_ipv4_addr? || server.saved_change_to_ipv6_addr?
            changed_ip_versions = []
            changed_ip_versions << 4 if server.saved_change_to_ipv4_addr?
            changed_ip_versions << 6 if server.saved_change_to_ipv6_addr?
            zones = server.dns_zones.existing.external_source.distinct.order(:id)
            zones.each(&:rotate_primary_transfer_generation!)
            reset_changed_source_states(server, zones, changed_ip_versions)

            zones.each do |zone|
              zone.dns_server_zones.existing.order(:id).each do |server_zone|
                TransactionChains::DnsServerZone::RefreshConfiguration.fire(server_zone)
              end
            end
          end
        end

        server
      end

      protected

      def reset_changed_source_states(server, zones, changed_ip_versions)
        server.dns_server_zones.existing
              .where(dns_zone_id: zones.select(:id))
              .order(:id)
              .each do |server_zone|
          server_zone.with_lock do
            states = server_zone.dns_server_zone_primary_transfer_states
                                .includes(dns_zone_transfer: :host_ip_address)
            state_ids = states.filter_map do |state|
              addr = ::IPAddress.parse(state.dns_zone_transfer.ip_addr)
              ip_version = addr.ipv4? ? 4 : 6
              state.id if changed_ip_versions.include?(ip_version)
            end
            ::DnsServerZonePrimaryTransferState.where(id: state_ids).delete_all
          end
        end
      end
    end

    class Delete < HaveAPI::Actions::Default::Delete
      desc 'Delete authoritative DNS server'

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        server = self.class.model.find(path_params['dns_server_id'])

        if server.dns_server_zones.any?
          error!('DNS server is in use, remove server zones first')
        end

        server.destroy!
        ok!
      end
    end
  end
end
