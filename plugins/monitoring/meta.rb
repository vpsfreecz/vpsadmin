VpsAdmin::API::Plugin.register(:monitoring) do
  name 'Monitoring'
  description 'Monitors resource usage and sends alerts'
  version '4.1.0'
  author 'Jakub Skokan'
  email 'jakub.skokan@vpsfree.cz'
  components :api

  config do
    SysConfig.register :plugin_monitoring, :alert_message_id, String,
                       default: '<vpsadmin-monitoring-alert-%{event_id}-%{alert_id}-%{state}@vpsadmin.vpsfree.cz>',
                       label: 'Alert message ID',
                       description: 'Mail header Message-ID used to put monitoring alert e-mails into threads',
                       min_user_level: 99

    VpsAdmin::API::Events.register(
      'monitoring.alert',
      label: 'Monitoring alert',
      category: 'monitoring',
      severity: :warning,
      default_routed: true,
      severity_description: 'Severity is derived from the monitoring alert state',
      parameters: {
        role: 'Recipient role',
        alert_kind: 'Monitoring alert kind',
        monitor_name: 'Monitor internal name',
        monitor_label: 'Monitor label',
        monitor_issue: 'Monitor issue description',
        monitored_event_id: 'Monitored event ID',
        state: 'Monitored event state',
        object_class: 'Monitored object class',
        object_id: 'Monitored object ID',
        object_label: 'Monitored object label',
        measured_value: 'Latest measured value',
        check_count: 'Number of recorded checks',
        alert_number: 'Alert sequence number',
        affected_user_id: 'Affected user ID',
        affected_user_login: 'Affected user login',
        vps_id: 'Affected VPS ID',
        vps_hostname: 'Affected VPS hostname',
        dataset_id: 'Affected dataset ID',
        dataset_full_name: 'Affected dataset name',
        dns_zone_id: 'Affected DNS zone ID',
        dns_zone_name: 'Affected DNS zone name',
        dns_server_id: 'DNS server ID',
        dns_server_name: 'DNS server name',
        transfer_status: 'DNS zone transfer status',
        transfer_reason_code: 'DNS transfer reason code',
        transfer_reason: 'DNS transfer reason',
        created_at: 'Monitored event creation time',
        updated_at: 'Monitored event update time',
        last_report_at: 'Last report time',
        saved_until: 'Acknowledged or ignored until',
        duration_seconds: 'Monitored event duration in seconds'
      }
    )
  end
end
