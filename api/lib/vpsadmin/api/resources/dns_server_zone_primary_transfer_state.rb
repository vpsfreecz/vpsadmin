module VpsAdmin::API::Resources
  class DnsServerZonePrimaryTransferState < HaveAPI::Resource
    PARAM_I18N = 'vpsadmin.resources.dns_server_zone_primary_transfer_state.attributes'.freeze

    model ::DnsServerZonePrimaryTransferState
    desc 'Browse current DNS primary transfer readiness by secondary server'

    params(:all) do
      integer :id,
              label: 'ID',
              desc: 'Transfer-readiness path ID',
              label_key: "#{PARAM_I18N}.id.label",
              desc_key: "#{PARAM_I18N}.id.description"
      resource DnsServerZone,
               value_label: :id,
               label: 'Managed secondary',
               desc: 'Managed secondary server whose direct transfer path was checked',
               label_key: "#{PARAM_I18N}.dns_server_zone.label",
               desc_key: "#{PARAM_I18N}.dns_server_zone.description"
      resource DnsZoneTransfer,
               value_label: :id,
               label: 'Configured primary',
               desc: 'Configured user primary checked from the managed secondary',
               label_key: "#{PARAM_I18N}.dns_zone_transfer.label",
               desc_key: "#{PARAM_I18N}.dns_zone_transfer.description"
      resource DnsServerZoneTransferLog, name: :last_transfer_log,
                                         value_label: :id,
                                         label: 'Latest diagnostic',
                                         desc: 'Latest retained diagnostic associated with this path state',
                                         label_key: "#{PARAM_I18N}.last_transfer_log.label",
                                         desc_key: "#{PARAM_I18N}.last_transfer_log.description",
                                         nullable: true
      string :status,
             label: 'Status',
             desc: 'Current direct transfer readiness of this primary-secondary path',
             label_key: "#{PARAM_I18N}.status.label",
             desc_key: "#{PARAM_I18N}.status.description",
             choices: ::DnsServerZonePrimaryTransferState.statuses.keys.map(&:to_s)
      string :failure_class,
             label: 'Failure class',
             desc: 'Whether the current failure is attributed to the primary or network path',
             label_key: "#{PARAM_I18N}.failure_class.label",
             desc_key: "#{PARAM_I18N}.failure_class.description",
             choices: ::DnsServerZonePrimaryTransferState.failure_classes.keys.map(&:to_s),
             nullable: true
      string :last_attempt_kind,
             label: 'Latest evidence source',
             desc: 'BIND operation or readiness probe that produced the latest path observation',
             label_key: "#{PARAM_I18N}.last_attempt_kind.label",
             desc_key: "#{PARAM_I18N}.last_attempt_kind.description",
             choices: ::DnsServerZonePrimaryTransferState.last_attempt_kinds.keys.map(&:to_s)
      datetime :failed_since,
               label: 'Failure started',
               desc: 'Start of the current continuous failure evidence',
               label_key: "#{PARAM_I18N}.failed_since.label",
               desc_key: "#{PARAM_I18N}.failed_since.description",
               nullable: true
      datetime :last_attempt_at,
               label: 'Latest check',
               desc: 'Time of the latest accepted observation for this path',
               label_key: "#{PARAM_I18N}.last_attempt_at.label",
               desc_key: "#{PARAM_I18N}.last_attempt_at.description"
      datetime :last_success_at,
               label: 'Latest success',
               desc: 'Time direct transfer readiness was last confirmed',
               label_key: "#{PARAM_I18N}.last_success_at.label",
               desc_key: "#{PARAM_I18N}.last_success_at.description",
               nullable: true
      datetime :reason_observed_at,
               label: 'Reason observed',
               desc: 'Time the displayed failure reason was observed',
               label_key: "#{PARAM_I18N}.reason_observed_at.label",
               desc_key: "#{PARAM_I18N}.reason_observed_at.description",
               nullable: true
      datetime :alert_eligible_at,
               label: 'Alert eligibility',
               desc: 'Time the continuous failure reached its notification delay',
               label_key: "#{PARAM_I18N}.alert_eligible_at.label",
               desc_key: "#{PARAM_I18N}.alert_eligible_at.description",
               nullable: true
      string :reason_code,
             label: 'Reason code',
             desc: 'Machine-readable reason for the current failure',
             label_key: "#{PARAM_I18N}.reason_code.label",
             desc_key: "#{PARAM_I18N}.reason_code.description",
             nullable: true
      string :reason,
             label: 'Reason',
             desc: 'Human-readable explanation of the current failure',
             label_key: "#{PARAM_I18N}.reason.label",
             desc_key: "#{PARAM_I18N}.reason.description",
             nullable: true
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
      string :secondary_source_addr,
             label: 'Transfer source address',
             desc: 'Managed secondary address used to contact this primary',
             label_key: "#{PARAM_I18N}.secondary_source_addr.label",
             desc_key: "#{PARAM_I18N}.secondary_source_addr.description",
             nullable: true
      datetime :created_at,
               label: 'Created at',
               desc: 'Time this path state was first recorded',
               label_key: "#{PARAM_I18N}.created_at.label",
               desc_key: "#{PARAM_I18N}.created_at.description"
      datetime :updated_at,
               label: 'Updated at',
               desc: 'Time this path state was last updated',
               label_key: "#{PARAM_I18N}.updated_at.label",
               desc_key: "#{PARAM_I18N}.updated_at.description"
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List current DNS primary transfer readiness paths'

      input do
        resource DnsZone,
                 label: 'DNS zone',
                 desc: 'Limit readiness paths to one DNS zone',
                 label_key: "#{PARAM_I18N}.dns_zone.label",
                 desc_key: "#{PARAM_I18N}.dns_zone.description"
        use :all, include: %i[dns_server_zone dns_zone_transfer status failure_class]
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
        allow
      end

      def query
        q = self.class.model
                .joins(:dns_zone_transfer, dns_server_zone: %i[dns_zone dns_server])
                .merge(::DnsServerZone.existing.secondary_type)
                .merge(::DnsZoneTransfer.existing.primary_type)
                .where(with_restricted)

        q = q.where(dns_server_zones: { dns_zone_id: input[:dns_zone].id }) if input[:dns_zone]
        %i[dns_server_zone dns_zone_transfer status failure_class].each do |param|
          q = q.where(param => input[param]) if input[param]
        end
        q
      end

      def count
        query.count
      end

      def exec
        with_pagination(with_includes(query)).order(:dns_zone_transfer_id, :dns_server_zone_id)
      end
    end
  end
end
