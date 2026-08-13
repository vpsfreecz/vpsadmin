module VpsAdmin::API::Resources
  class DnsServerZoneTransferLog < HaveAPI::Resource
    PARAM_I18N = 'vpsadmin.resources.dns_server_zone_transfer_log.attributes'.freeze

    model ::DnsServerZoneTransferLog
    desc 'Browse DNS zone transfer logs'

    params(:all) do
      integer :id, label: 'ID'
      resource DnsServerZone, value_label: :id, label: 'DNS server zone'
      resource DnsZoneTransfer,
               value_label: :id,
               label: 'Configured primary',
               desc: 'Configured user primary associated with this diagnostic',
               label_key: "#{PARAM_I18N}.dns_zone_transfer.label",
               desc_key: "#{PARAM_I18N}.dns_zone_transfer.description",
               nullable: true
      datetime :event_at
      string :status, choices: ::DnsServerZoneTransferLog.statuses.keys.map(&:to_s)
      string :attempt_kind,
             label: 'Attempt kind',
             desc: 'Real BIND transfer, readiness probe, validation probe, or supporting operation',
             choices: ::DnsServerZoneTransferLog.attempt_kinds.keys.map(&:to_s)
      string :failure_class,
             label: 'Failure class',
             desc: 'Responsibility category assigned to a failed operation',
             choices: ::DnsServerZoneTransferLog.failure_classes.keys.map(&:to_s),
             nullable: true
      string :reason_code, label: 'Reason code'
      string :reason
      string :primary_addr
      integer :serial
      integer :primary_serial,
              label: 'Primary serial',
              desc: 'SOA serial observed on the configured primary',
              label_key: "#{PARAM_I18N}.primary_serial.label",
              desc_key: "#{PARAM_I18N}.primary_serial.description",
              nullable: true
      integer :secondary_serial,
              label: 'Secondary serial',
              desc: 'SOA serial loaded on the managed secondary',
              label_key: "#{PARAM_I18N}.secondary_serial.label",
              desc_key: "#{PARAM_I18N}.secondary_serial.description",
              nullable: true
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
        use :all, include: %i[dns_server_zone dns_zone_transfer status
                              attempt_kind failure_class reason_code primary_addr]
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
        input whitelist: %i[dns_zone dns_server_zone dns_zone_transfer status
                            attempt_kind failure_class reason_code primary_addr
                            order from_id limit]
        output blacklist: %i[raw_message source_cursor event_key]
        allow
      end

      def query
        q = self.class.model
                .joins(dns_server_zone: %i[dns_zone dns_server])
                .where(with_restricted)

        unless current_user.role == :admin
          q = q.where(
            'dns_server_zone_transfer_logs.dns_zone_transfer_id IS NOT NULL AND ' \
            '(dns_server_zone_transfer_logs.status = :success OR ' \
            'dns_server_zone_transfer_logs.failure_class IN (:actionable))',
            success: ::DnsServerZoneTransferLog.statuses[:success],
            actionable: [
              ::DnsServerZoneTransferLog.failure_classes[:primary],
              ::DnsServerZoneTransferLog.failure_classes[:network]
            ]
          )
        end

        q = q.where(dns_server_zones: { dns_zone_id: input[:dns_zone].id }) if input[:dns_zone]

        %i[dns_server_zone dns_zone_transfer status attempt_kind failure_class
           reason_code primary_addr].each do |v|
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
          with_asc_pagination(q).order(
            'dns_server_zone_transfer_logs.event_at ASC, dns_server_zone_transfer_logs.id ASC'
          )
        when 'latest'
          with_desc_pagination(q).order(
            'dns_server_zone_transfer_logs.event_at DESC, dns_server_zone_transfer_logs.id DESC'
          )
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
        q = self.class.model
                .joins(dns_server_zone: %i[dns_zone dns_server])
                .where(with_restricted(id: path_params['dns_server_zone_transfer_log_id']))

        unless current_user.role == :admin
          q = q.where(
            'dns_server_zone_transfer_logs.dns_zone_transfer_id IS NOT NULL AND ' \
            '(dns_server_zone_transfer_logs.status = :success OR ' \
            'dns_server_zone_transfer_logs.failure_class IN (:actionable))',
            success: ::DnsServerZoneTransferLog.statuses[:success],
            actionable: [
              ::DnsServerZoneTransferLog.failure_classes[:primary],
              ::DnsServerZoneTransferLog.failure_classes[:network]
            ]
          )
        end

        @log = q.take!
      end

      def exec
        @log
      end
    end
  end
end
