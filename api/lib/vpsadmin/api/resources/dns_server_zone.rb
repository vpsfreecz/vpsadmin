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
      datetime :last_transfer_at
      string :last_transfer_status, choices: ::DnsServerZone.last_transfer_statuses.keys.map(&:to_s)
      string :last_transfer_reason_code
      string :last_transfer_reason
      string :last_transfer_primary_addr
      integer :last_transfer_serial
      integer :last_transfer_log_id
      datetime :created_at
      datetime :updated_at
    end

    class MaskedTransferState
      MASKED = %i[
        last_transfer_at
        last_transfer_status
        last_transfer_reason_code
        last_transfer_reason
        last_transfer_primary_addr
        last_transfer_serial
        last_transfer_log_id
      ].freeze

      def initialize(server_zone)
        @server_zone = server_zone
      end

      def respond_to_missing?(name, include_private = false)
        return false if MASKED.include?(name.to_sym)

        @server_zone.respond_to?(name, include_private)
      end

      def method_missing(name, *, &)
        return super if MASKED.include?(name.to_sym)

        @server_zone.public_send(name, *, &)
      end
    end

    def self.mask_transfer_state(server_zone, user)
      if user.role != :admin && server_zone.dns_zone.internal_source?
        MaskedTransferState.new(server_zone)
      else
        server_zone
      end
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
        restrict dns_zones: { user_id: u.id }, dns_servers: { hidden: false }
        allow
      end

      def query
        q = self.class.model.existing.joins(:dns_zone, :dns_server).where(with_restricted)

        %w[dns_server dns_zone].each do |v|
          q = q.where(v => input[v]) if input[v]
        end

        q
      end

      def count
        query.count
      end

      def exec
        q = with_pagination(with_includes(query))
        return q if current_user.role == :admin

        q.map { |server_zone| self.class.resource.mask_transfer_state(server_zone, current_user) }
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show DNS zone on server'

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict dns_zones: { user_id: u.id }, dns_servers: { hidden: false }
        allow
      end

      def prepare
        @server_zone = with_includes(self.class.model.existing.joins(:dns_zone, :dns_server).where(with_restricted(id: params[:dns_server_zone_id]))).take!
      end

      def exec
        self.class.resource.mask_transfer_state(@server_zone, current_user)
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      desc 'Add DNS zone to a server'
      blocking true

      input do
        use :common
        patch :dns_server, required: true
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
        error!('create failed', e.record.errors.to_hash)
      rescue ActiveRecord::RecordNotUnique => e
        error!("zone #{input[:dns_zone].name} already is on server #{input[:dns_server].name}")
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
        ok!
      end

      def state_id
        @chain.id
      end
    end

    class TransferLog < HaveAPI::Resource
      route '{dns_server_zone_id}/transfer_logs'
      model ::DnsServerZoneTransferLog
      desc 'Browse DNS zone transfer logs'

      params(:all) do
        integer :id, label: 'ID'
        resource DnsServerZone, value_label: :id
        datetime :event_at
        string :status, choices: ::DnsServerZoneTransferLog.statuses.keys.map(&:to_s)
        string :reason_code
        string :reason
        string :primary_addr
        integer :serial
        text :message
        text :raw_message
        string :source_cursor
        string :event_key
        datetime :created_at
        datetime :updated_at
      end

      class Index < HaveAPI::Actions::Default::Index
        desc 'List DNS zone transfer logs'

        input do
          use :all, include: %i[status reason_code primary_addr]
          string :order, choices: %w[oldest latest], default: 'latest', fill: true
          patch :limit, default: 25, fill: true
        end

        output(:object_list) do
          use :all
        end

        authorize do |u|
          allow if u.role == :admin
          restrict dns_server_zones: {
            dns_zones: { user_id: u.id, zone_source: 'external_source' },
            dns_servers: { hidden: false }
          }
          output blacklist: %i[raw_message source_cursor event_key]
          allow
        end

        def query
          q = self.class.model
                  .joins(dns_server_zone: %i[dns_zone dns_server])
                  .where(with_restricted(dns_server_zone_id: params[:dns_server_zone_id]))

          %i[status reason_code primary_addr].each do |v|
            q = q.where(v => input[v]) if input[v]
          end

          q
        end

        def count
          query.count
        end

        def prepare
          q = ::DnsServerZone.joins(:dns_zone, :dns_server).where(id: params[:dns_server_zone_id])

          if current_user.role != :admin
            q = q.where(
              dns_zones: { user_id: current_user.id, zone_source: 'external_source' },
              dns_servers: { hidden: false }
            )
          end

          @server_zone = q.take!
        end

        def exec
          q = with_includes(query)

          case input[:order]
          when 'oldest'
            with_asc_pagination(q).order('event_at')
          when 'latest'
            with_desc_pagination(q).order('event_at DESC')
          end
        end
      end

      class Show < HaveAPI::Actions::Default::Show
        desc 'Show DNS zone transfer log'

        output do
          use :all
        end

        authorize do |u|
          allow if u.role == :admin
          restrict dns_server_zones: {
            dns_zones: { user_id: u.id, zone_source: 'external_source' },
            dns_servers: { hidden: false }
          }
          output blacklist: %i[raw_message source_cursor event_key]
          allow
        end

        def prepare
          @log = self.class.model
                     .joins(dns_server_zone: %i[dns_zone dns_server])
                     .where(with_restricted(
                              dns_server_zone_id: params[:dns_server_zone_id],
                              id: params[:transfer_log_id]
                            ))
                     .take!
        end

        def exec
          @log
        end
      end
    end
  end
end
