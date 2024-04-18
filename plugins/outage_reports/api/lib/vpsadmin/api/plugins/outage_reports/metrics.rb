module VpsAdmin::API::Plugins::OutageReports
  class Metrics < VpsAdmin::API::Plugin::MetricsBase
    def setup
      label_list = %i[
        outage_id
        outage_begins_at
        outage_duration
        outage_type
        outage_impact
        node_id
        node_name
        location_id
        location_label
      ]

      ::Language.all.each do |lang|
        label_list << :"outage_summary_#{lang.code}"
      end

      @vps_outage_report = add_metric(
        :gauge,
        :vps_outage_report,
        docstring: 'Outage report affecting VPS',
        labels: label_list + %i[vps_id]
      )

      @export_outage_report = add_metric(
        :gauge,
        :export_outage_report,
        docstring: 'Outage report affecting NFS export',
        labels: label_list + %i[export_id export_address export_path]
      )
    end

    def compute
      ::Outage.where(state: 'announced').each do |outage|
        next unless outage.affected(user:)

        outage_user = outage.outage_users.find_by(user:)
        next if outage_user.nil?

        # rubocop:disable Style/Next

        if outage_user.vps_count > 0
          outage.outage_vpses.where(user:).each do |outage_vps|
            @vps_outage_report.set(1, labels: vps_outage_labels(outage, outage_vps))
          end
        end

        if outage_user.export_count > 0
          outage.outage_exports.where(user:).each do |outage_export|
            @export_outage_report.set(1, labels: export_outage_labels(outage, outage_export))
          end
        end

        # rubocop:enable Style/Next
      end
    end

    protected

    def vps_outage_labels(outage, outage_vps)
      outage_labels(outage, outage_vps.vps.node).merge(vps_id: outage_vps.vps_id)
    end

    def export_outage_labels(outage, outage_export)
      outage_labels(outage, outage_export.export.dataset_in_pool.pool.node).merge(
        export_id: outage_export.export_id,
        export_address: outage_export.export.network_interface.ip_addresses.take.host_ip_addresses.take.ip_addr,
        export_path: outage_export.export.path
      )
    end

    def outage_labels(outage, node)
      ret = {
        outage_id: outage.id,
        outage_begins_at: outage.begins_at.to_s,
        outage_duration: outage.duration,
        outage_type: outage.outage_type,
        outage_impact: outage.impact_type,
        node_id: node.id,
        node_name: node.domain_name,
        location_id: node.location.id,
        location_label: node.location.label
      }

      ::Language.all.each do |lang|
        ret[:"outage_summary_#{lang.code}"] = outage.send(:"#{lang.code}_summary")
      end

      ret
    end
  end
end
