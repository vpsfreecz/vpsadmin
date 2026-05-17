module VpsAdmin::API::Resources
  class DnsServerZoneTransferLog < HaveAPI::Resource
    model ::DnsServerZoneTransferLog
    desc 'Browse DNS zone transfer logs'

    params(:all) do
      integer :id, label: 'ID'
      resource DnsServerZone, value_label: :id, label: 'DNS server zone'
      datetime :event_at
      string :status, choices: ::DnsServerZoneTransferLog.statuses.keys.map(&:to_s)
      string :reason_code, label: 'Reason code'
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
        resource DnsZone, value_label: :name, label: 'DNS zone'
        use :all, include: %i[dns_server_zone status reason_code primary_addr]
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
                .where(with_restricted)

        q = q.where(dns_server_zones: { dns_zone_id: input[:dns_zone].id }) if input[:dns_zone]

        %i[dns_server_zone status reason_code primary_addr].each do |v|
          q = q.where(v => input[v]) if input[v]
        end

        q
      end

      def count
        query.count
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
                   .where(with_restricted(id: params[:dns_server_zone_transfer_log_id]))
                   .take!
      end

      def exec
        @log
      end
    end
  end
end
