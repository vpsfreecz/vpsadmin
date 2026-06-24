module VpsAdmin::API::Events::Core
  module_function

  def param(event, name)
    params = event.parameters || {}
    params[name.to_s] || params[name.to_sym]
  end

  def params(event)
    event.parameters || {}
  end

  def base_url
    ::SysConfig.get(:webui, :base_url)
  end

  def parse_time(value)
    VpsAdmin::API::Events.parse_time(value)
  end

  def truthy_param(value)
    value == true || value.to_s == 'true' || value.to_s == '1'
  end

  def numeric_param(value)
    return if value.blank?

    Float(value)
  rescue ArgumentError, TypeError
    nil
  end

  def bounded_collection_count(value)
    count = value.to_i
    return 0 if count < 0

    [count, VpsAdmin::API::Events::FALLBACK_COLLECTION_LIMIT].min
  end

  def user_info_from_parameters(params, prefix)
    login = params["#{prefix}_login"] || params[:"#{prefix}_login"]
    full_name = params["#{prefix}_name"] || params[:"#{prefix}_name"] || login
    return if full_name.blank?

    VpsAdmin::API::Events::UserInfo.new(
      id: params["#{prefix}_id"] || params[:"#{prefix}_id"],
      login: login || full_name,
      full_name:
    )
  end

  def object_state_source(event)
    event.source if event.source.is_a?(::ObjectState)
  end

  def object_state_from_parameters(event)
    p = params(event)

    VpsAdmin::API::Events::ObjectStateInfo.new(
      state: p['state'] || p[:state],
      reason: p['reason'] || p[:reason],
      expiration_date: parse_time(p['expiration_date'] || p[:expiration_date]),
      user: user_info_from_parameters(p, 'changed_by')
    )
  end

  def user_owned_source(event, model)
    source = event.source
    return unless source.is_a?(model)
    return if event.user_id.present? && source.user_id != event.user_id

    source
  end

  def find_from_parameters(event, model, key)
    value = param(event, key)
    return if value.blank?

    scope = model.all
    if event.user_id.present? && model.column_names.include?('user_id')
      scope = scope.where(user_id: event.user_id)
    end

    scope.find_by(id: value)
  end

  def required_vps(event)
    vps = event.vps
    raise ArgumentError, "#{event.event_type} VPS is missing" unless vps

    if event.user_id.present? && vps.user_id != event.user_id
      raise ArgumentError, "#{event.event_type} VPS does not belong to event user"
    end

    vps
  end

  def user_source(event)
    source = event.source
    return unless source.is_a?(::User)
    return if event.user_id.present? && source.id != event.user_id

    source
  end

  def user_session_source(event)
    user_owned_source(event, ::UserSession)
  end

  def user_totp_device_source(event)
    user_owned_source(event, ::UserTotpDevice)
  end

  def user_email_vars(event)
    {
      user: event.user || user_source(event)
    }
  end

  def user_state_email_vars(event)
    {
      user: event.user,
      state: object_state_source(event) || object_state_from_parameters(event)
    }
  end

  def user_new_login_email_vars(event, session: nil, authorization: nil)
    session ||= user_session_source(event)
    authorization ||= find_from_parameters(event, ::Oauth2Authorization, 'authorization_id')
    user_device = authorization&.user_device ||
                  find_from_parameters(event, ::UserDevice, 'user_device_id')

    {
      user: event.user || session&.user,
      user_session: session,
      authorization:,
      user_device:
    }
  end

  def user_new_token_email_vars(event)
    session = user_session_source(event)

    {
      user: event.user || session&.user,
      user_session: session
    }
  end

  def user_totp_recovery_email_vars(event)
    request_ip = param(event, 'request_ip')
    totp_device = user_totp_device_source(event) ||
                  find_from_parameters(event, ::UserTotpDevice, 'totp_device_id')

    {
      user: event.user,
      totp_device:,
      request: request_ip.present? ? VpsAdmin::API::Events::RequestInfo.new(request_ip) : nil,
      time: parse_time(param(event, 'used_at')) || event.created_at
    }
  end

  def failed_login_groups(event)
    group_ids = Array(param(event, 'attempt_group_ids'))
    ids = group_ids.flatten.map(&:to_i).uniq
    return [] if ids.empty?

    attempts = ::UserFailedLogin
               .includes(:user_agent)
               .where(user_id: event.user_id)
               .where(id: ids)
               .to_a
               .index_by(&:id)

    group_ids.map do |group|
      Array(group).filter_map { |id| attempts[id.to_i] }
    end
  end

  def user_failed_logins_email_vars(event)
    {
      user: event.user,
      attempt_groups: failed_login_groups(event)
    }
  end

  def expiration_warning_object(event)
    case param(event, 'object')
    when 'user'
      event.user
    when 'vps'
      required_vps(event)
    else
      source = event.source
      return if source.nil?
      return unless source.respond_to?(:user_id)
      return if event.user_id.present? && source.user_id != event.user_id

      source
    end
  end

  def expiration_warning_email_vars(event)
    object = expiration_warning_object(event)
    object_key = param(event, 'object')
    state = object_state_from_parameters(event)
    expires_in_days = numeric_param(param(event, 'expires_in_days'))
    expired_days_ago = numeric_param(param(event, 'expired_days_ago'))

    ret = {
      base_url:,
      user: event.user,
      object:,
      state:,
      expires_in_days:,
      expired_days_ago:,
      expires_in_a_day: truthy_param(param(event, 'expires_in_a_day'))
    }
    ret[object_key] = object if object_key.present?
    ret
  end

  def incident_email_vars(event)
    incident = event.source if event.source.is_a?(::IncidentReport)
    raise ArgumentError, 'incident report source is missing' unless incident

    {
      base_url:,
      user: incident.user,
      vps: incident.vps,
      incident:
    }
  end

  def oom_reports_from_ids(event, ids)
    ids = Array(ids).map(&:to_i).uniq
    return [] if ids.empty?

    reports = oom_report_scope(event).where(id: ids).to_a.index_by(&:id)
    ids.filter_map { |id| reports[id] }
  end

  def oom_reports_from_batch(event, selected_reports)
    batch_time = parse_time(param(event, 'batch_reported_at'))
    return selected_reports if batch_time.nil?

    scope = oom_report_scope(event).order('oom_reports.created_at')
    last_reported_id = param(event, 'last_reported_id')
    scope = scope.where('oom_reports.id > ?', last_reported_id.to_i) if last_reported_id.present?
    scope = scope.where('oom_reports.created_at <= ?', batch_time)
    scope.to_a
  end

  def oom_report_scope(event)
    raise ArgumentError, 'OOM report event has no user' if event.user_id.blank?

    scope = ::OomReport.joins(:vps).where(vpses: { user_id: event.user_id })
    scope = scope.where(vps_id: event.vps_id) if event.vps_id.present?
    scope.where(ignored: false)
  end

  def oom_report_email_vars(event)
    selected_reports = oom_reports_from_ids(event, param(event, 'selected_report_ids'))
    reports = oom_reports_from_batch(event, selected_reports)

    raise ArgumentError, 'OOM report parameters are missing report ids' if reports.empty?

    selected_reports = reports.first(30) if selected_reports.empty?

    {
      base_url:,
      vps: event.vps || reports.first.vps,
      all_oom_reports: reports,
      all_oom_count: param(event, 'oom_count') || reports.sum(&:count),
      selected_oom_reports: selected_reports,
      selected_oom_count: param(event, 'selected_oom_count') || selected_reports.sum(&:count)
    }
  end

  def oom_prevention_email_vars(event)
    vps = event.vps
    raise ArgumentError, 'OOM prevention VPS is missing' unless vps

    {
      base_url:,
      vps:,
      action: param(event, 'action')&.to_sym,
      ooms_in_period: param(event, 'ooms_in_period'),
      period_seconds: param(event, 'period_seconds')
    }
  end

  def vps_state_email_vars(event)
    {
      vps: required_vps(event),
      state: object_state_source(event) || object_state_from_parameters(event)
    }
  end

  def vps_resources_email_vars(event)
    {
      vps: required_vps(event),
      admin: user_info_from_parameters(params(event), 'admin'),
      reason: param(event, 'reason')
    }
  end

  def dns_resolver_from_parameters(event, prefix)
    p = params(event)

    VpsAdmin::API::Events::DnsResolverInfo.new(
      id: p["#{prefix}_dns_resolver_id"] || p[:"#{prefix}_dns_resolver_id"],
      label: p["#{prefix}_dns_resolver_label"] || p[:"#{prefix}_dns_resolver_label"],
      addrs: p["#{prefix}_dns_resolver_addrs"] || p[:"#{prefix}_dns_resolver_addrs"] || ''
    )
  end

  def vps_dns_resolver_email_vars(event)
    {
      vps: required_vps(event),
      old_dns_resolver: dns_resolver_from_parameters(event, 'old'),
      new_dns_resolver: dns_resolver_from_parameters(event, 'new')
    }
  end

  def vps_network_email_vars(event)
    {
      user: event.user,
      vps: required_vps(event),
      reason: param(event, 'reason') || ''
    }
  end

  def dataset_expansion_source(event)
    source = event.source
    return unless source.is_a?(::DatasetExpansion)
    return if event.vps_id.present? && source.vps_id != event.vps_id
    return if event.user_id.present? && source.vps.user_id != event.user_id

    source
  end

  def dataset_expansion_from_parameters(event)
    VpsAdmin::API::Events::DatasetExpansionInfo.new(
      id: param(event, 'expansion_id'),
      original_refquota: param(event, 'original_refquota').to_i,
      added_space: param(event, 'added_space').to_i,
      expansion_count: param(event, 'expansion_count').to_i,
      over_refquota_seconds: param(event, 'over_refquota_seconds').to_i,
      max_over_refquota_seconds: param(event, 'max_over_refquota_seconds').to_i,
      enable_shrink: param(event, 'enable_shrink')
    )
  end

  def dataset_from_parameters(event)
    VpsAdmin::API::Events::DatasetInfo.new(
      id: param(event, 'dataset_id'),
      full_name: param(event, 'dataset_full_name'),
      refquota: param(event, 'dataset_refquota').to_i,
      referenced: param(event, 'dataset_referenced').to_i,
      user: event.user || user_info_from_parameters(params(event), 'user')
    )
  end

  def vps_dataset_expansion_email_vars(event)
    expansion = dataset_expansion_source(event) || dataset_expansion_from_parameters(event)
    dataset = expansion.is_a?(::DatasetExpansion) ? expansion.dataset : dataset_from_parameters(event)

    {
      base_url:,
      vps: required_vps(event),
      expansion:,
      dataset:
    }
  end

  def snapshot_download_source(event)
    source = event.source
    return unless source.is_a?(::SnapshotDownload)
    return if event.user_id.present? && source.user_id != event.user_id

    source
  end

  def snapshot_download_email_vars(event)
    download = snapshot_download_source(event)
    return { base_url:, dl: download } if download

    dataset = dataset_from_parameters(event)
    snapshot = VpsAdmin::API::Events::SnapshotInfo.new(
      id: param(event, 'snapshot_id'),
      name: param(event, 'snapshot_name'),
      dataset:
    )
    download = VpsAdmin::API::Events::SnapshotDownloadInfo.new(
      id: param(event, 'download_id'),
      file_name: param(event, 'file_name'),
      expiration_date: parse_time(param(event, 'expiration_date')),
      user: event.user,
      snapshot:
    )

    {
      base_url:,
      dl: download
    }
  end

  def node_info_from_parameters(event, prefix)
    p = params(event)

    VpsAdmin::API::Events::NodeInfo.new(
      id: p["#{prefix}_node_id"] || p[:"#{prefix}_node_id"],
      domain_name: p["#{prefix}_node_domain_name"] || p[:"#{prefix}_node_domain_name"]
    )
  end

  def pool_info_from_parameters(event, prefix)
    p = params(event)

    VpsAdmin::API::Events::PoolInfo.new(
      id: p["#{prefix}_pool_id"] || p[:"#{prefix}_pool_id"],
      filesystem: p["#{prefix}_pool_filesystem"] || p[:"#{prefix}_pool_filesystem"]
    )
  end

  def vps_infos_from_parameters(event)
    Array(param(event, 'affected_vpses')).map do |item|
      data = item.respond_to?(:to_h) ? item.to_h : {}
      VpsAdmin::API::Events::VpsInfo.new(
        id: data['id'] || data[:id],
        hostname: data['hostname'] || data[:hostname],
        user: event.user
      )
    end
  end

  def dataset_source(event)
    source = event.source
    return unless source.is_a?(::Dataset)
    return if event.user_id.present? && source.user_id != event.user_id

    source
  end

  def dataset_migration_email_vars(event, vpses: nil)
    dataset = dataset_source(event) || dataset_from_parameters(event)

    {
      dataset:,
      src_pool: pool_info_from_parameters(event, 'src'),
      dst_pool: pool_info_from_parameters(event, 'dst'),
      exports: Array.new(bounded_collection_count(param(event, 'export_count'))),
      export_mounts: [],
      vpses: vpses || vps_infos_from_parameters(event),
      restart_vps: truthy_param(param(event, 'restart_vps')),
      maintenance_window: truthy_param(param(event, 'maintenance_window')),
      maintenance_windows: [],
      custom_window: truthy_param(param(event, 'custom_window')),
      finish_weekday: param(event, 'finish_weekday'),
      finish_minutes: param(event, 'finish_minutes'),
      reason: param(event, 'reason')
    }
  end

  def vps_migration_source(event)
    source = event.source
    return unless source.is_a?(::VpsMigration)
    return if event.user_id.present? && source.vps.user_id != event.user_id

    source
  end

  def vps_migration_email_vars(event)
    {
      m: vps_migration_source(event) || VpsAdmin::API::Events::VpsMigrationInfo.new(
        id: param(event, 'migration_id'),
        maintenance_window: truthy_param(param(event, 'maintenance_window'))
      ),
      vps: required_vps(event),
      src_node: node_info_from_parameters(event, 'src'),
      dst_node: node_info_from_parameters(event, 'dst'),
      maintenance_window: truthy_param(param(event, 'maintenance_window')),
      maintenance_windows: [],
      custom_window: truthy_param(param(event, 'custom_window')),
      finish_weekday: param(event, 'finish_weekday'),
      finish_minutes: param(event, 'finish_minutes'),
      reason: param(event, 'reason')
    }
  end

  def find_vps_from_parameters(event, key)
    value = param(event, key)
    return if value.blank?

    scope = ::Vps.including_deleted
    scope = scope.where(user_id: event.user_id) if event.user_id.present?
    scope.find_by(id: value)
  end

  def vps_info_from_parameters(event, prefix)
    p = params(event)
    hostname = p["#{prefix}_vps_hostname"] || p[:"#{prefix}_vps_hostname"]
    return if hostname.blank?

    VpsAdmin::API::Events::VpsInfo.new(
      id: p["#{prefix}_vps_id"] || p[:"#{prefix}_vps_id"],
      hostname:,
      user: event.user
    )
  end

  def secondary_vps_source(event)
    source = event.source
    return unless source.is_a?(::Vps)
    return if event.vps_id.present? && source.id == event.vps_id
    return if event.user_id.present? && source.user_id != event.user_id

    source
  end

  def vps_replaced_email_vars(event)
    new_vps = secondary_vps_source(event) ||
              find_vps_from_parameters(event, 'new_vps_id') ||
              vps_info_from_parameters(event, 'new')

    {
      original_vps: required_vps(event),
      new_vps:,
      reason: param(event, 'reason')
    }
  end

  def security_advisory_source(event)
    case event.source
    when ::SecurityAdvisory
      event.source
    when ::SecurityAdvisoryUpdate
      event.source.security_advisory
    end
  end

  def security_advisory_update_source(event, advisory)
    source = event.source
    return unless source.is_a?(::SecurityAdvisoryUpdate)
    return unless source.security_advisory_id == advisory.id

    source
  end

  def security_advisory_from_parameters(event)
    advisory_id = param(event, 'advisory_id')
    return if advisory_id.blank?

    ::SecurityAdvisory.visible_to(event.user).find_by(id: advisory_id)
  end

  def security_advisory_update_from_parameters(event, advisory)
    update_id = param(event, 'update_id')
    return if update_id.blank?

    advisory.security_advisory_updates.find_by(id: update_id)
  end

  def security_advisory_vpses_for(advisory, user)
    scope = advisory.security_advisory_vpses.includes(:vps, :node).order(:vps_id)
    return scope.none unless user

    scope.where(user:)
  end

  def security_advisory_email_vars(event)
    advisory = security_advisory_source(event) ||
               security_advisory_from_parameters(event)
    raise ArgumentError, 'security advisory is missing' unless advisory

    update = security_advisory_update_source(event, advisory) ||
             security_advisory_update_from_parameters(event, advisory)
    if event.event_type == 'security_advisory.updated' && update.nil?
      raise ArgumentError, 'security advisory update is missing'
    end

    {
      advisory:,
      a: advisory,
      update:,
      user: event.user,
      vpses: security_advisory_vpses_for(advisory, event.user),
      webui_url: VpsAdmin::API::Events.webui_url
    }
  end

  def system_report_language(event)
    language = ::Language.find_by(id: param(event, 'language_id'))
    language ||= ::Language.find_by(code: param(event, 'language_code'))
    language || ::Language.take
  end
end

VpsAdmin::API::Events.define do
  event 'user.created',
        label: 'User account created',
        category: 'account',
        severity: :info,
        default_routed: true do
    parameters(
      login: 'User login',
      email: 'User e-mail',
      level: 'User level',
      object_state: 'Initial account state',
      create_vps: 'Whether an initial VPS was requested',
      active: 'Whether the account was activated'
    )

    deliver :email do
      template :user_create
      vars { VpsAdmin::API::Events::Core.user_email_vars(event) }
    end
  end

  %w[
    user.suspended
    user.soft_deleted
    user.resumed
    user.revived
  ].each do |event_name|
    labels = {
      'user.suspended' => ['User account suspended', :warning, :user_suspend],
      'user.soft_deleted' => ['User account disabled', :warning, :user_soft_delete],
      'user.resumed' => ['User account resumed', :info, :user_resume],
      'user.revived' => ['User account restored', :info, :user_revive]
    }
    label, severity, template = labels.fetch(event_name)

    event event_name,
          label:,
          category: 'account',
          severity:,
          default_routed: true do
      parameters(
        state: 'Lifecycle state',
        reason: 'Lifecycle reason',
        expiration_date: 'Expiration date'
      )

      deliver :email do
        template template
        vars { VpsAdmin::API::Events::Core.user_state_email_vars(event) }
      end
    end
  end

  event 'user.new_token',
        label: 'New access token',
        category: 'security',
        severity: :warning,
        default_routed: true do
    parameters(
      auth_type: 'Authentication type',
      client_ip_addr: 'Client IP address',
      api_ip_addr: 'API IP address',
      client_version: 'Client version',
      scope: 'Token scope',
      token_lifetime: 'Token lifetime',
      label: 'Token label'
    )

    deliver :email do
      template :user_new_token
      vars { VpsAdmin::API::Events::Core.user_new_token_email_vars(event) }
    end
  end

  event 'user.totp_recovery_code_used',
        label: 'TOTP recovery code used',
        category: 'security',
        severity: :critical,
        default_routed: true do
    parameters(
      totp_device_id: 'TOTP device ID',
      totp_device_label: 'TOTP device label',
      request_ip: 'Request IP address',
      used_at: 'Recovery time'
    )

    deliver :email do
      template :user_totp_recovery_code_used
      vars { VpsAdmin::API::Events::Core.user_totp_recovery_email_vars(event) }
    end
  end

  event 'user.failed_logins',
        label: 'Failed sign-in report',
        category: 'security',
        severity: :warning,
        default_routed: true do
    parameters(
      attempt_count: 'Failed attempt count',
      group_count: 'Attempt group count',
      attempt_group_ids: 'Failed attempt IDs grouped by similarity',
      ip_addrs: 'Client IP addresses',
      auth_types: 'Authentication types',
      reasons: 'Failure reasons'
    )

    deliver :email do
      template :user_failed_logins
      vars { VpsAdmin::API::Events::Core.user_failed_logins_email_vars(event) }
    end
  end

  event 'user.test_notification',
        label: 'Test notification',
        category: 'test',
        severity: :info,
        default_routed: true do
    parameters(note: 'Test note')
  end

  event 'user.new_login',
        label: 'New sign-in',
        category: 'security',
        severity: :warning,
        default_routed: true do
    argument :session, type: 'UserSession'
    argument :authorization, type: 'Oauth2Authorization'

    user { session.user }
    source { session }
    subject { 'New sign-in' }
    summary { "New sign-in to #{session.user.login}" }
    ip_addr { session.client_ip_addr || session.api_ip_addr }

    parameter(:auth_type, 'Authentication type') { session.auth_type }
    parameter(:client_ip_addr, 'Client IP address') { session.client_ip_addr }
    parameter(:api_ip_addr, 'API IP address') { session.api_ip_addr }
    parameter(:client_version, 'Client version') { session.client_version }
    parameter(:user_agent, 'User agent') { session.user_agent_string }
    parameter(:user_device_id, 'User device ID') { authorization.user_device&.id }
    parameter(:authorization_id, 'OAuth authorization ID') { authorization.id }
    parameter(:oauth2_client_id, 'OAuth client ID') { authorization.oauth2_client_id }

    deliver :email do
      template :user_new_login
      vars do
        VpsAdmin::API::Events::Core.user_new_login_email_vars(
          event,
          session: respond_to?(:session) ? session : nil,
          authorization: respond_to?(:authorization) ? authorization : nil
        )
      end
    end
  end

  event 'transaction_chain.state_changed',
        label: 'Transaction chain state changed',
        category: 'transactions',
        severity: :info,
        default_routed: false,
        severity_description: 'Severity is derived from the new transaction chain state' do
    parameters(
      chain_id: 'Transaction chain ID',
      chain_name: 'Transaction chain internal name',
      chain_label: 'Transaction chain label',
      previous_state: 'Previous state',
      state: 'Current state',
      terminal: 'Whether the chain reached a terminal state',
      successful: 'Whether the terminal state is successful',
      failed: 'Whether the terminal state is failed or fatal',
      size: 'Number of transactions in the chain',
      progress: 'Finished transaction count',
      user_session_id: 'User session ID',
      concerns: 'Affected objects',
      node_id: 'Node ID that reported the change',
      node_name: 'Node name that reported the change',
      changed_at: 'State change time',
      changed_at_timestamp: 'State change Unix timestamp'
    )
  end

  %w[dns.zone_transfer.failed dns.zone_transfer.recovered].each do |event_name|
    event event_name,
          label: event_name.end_with?('failed') ? 'DNS zone transfer failed' : 'DNS zone transfer recovered',
          category: 'dns',
          severity: event_name.end_with?('failed') ? :warning : :info,
          default_routed: false do
      parameters(
        transfer_log_id: 'DNS transfer log ID',
        dns_zone_id: 'DNS zone ID',
        dns_zone_name: 'DNS zone name',
        dns_server_zone_id: 'DNS server zone ID',
        dns_server_id: 'DNS server ID',
        dns_server_name: 'DNS server name',
        node_id: 'Node ID',
        node_name: 'Node name',
        previous_status: 'Previous transfer status',
        status: 'Transfer status',
        reason_code: 'Failure reason code',
        reason: 'Failure reason',
        primary_addr: 'Primary server address',
        serial: 'Transferred serial',
        message: 'Transfer message',
        event_at: 'Transfer event time'
      )
    end
  end

  event 'system.daily_report',
        label: 'Daily report',
        category: 'system',
        severity: :info,
        default_routed: true do
    argument :report_vars, type: Hash, optional: true

    parameters(
      language_id: 'Notification language ID',
      language_code: 'Notification language code',
      period_start: 'Report period start',
      period_end: 'Report period end',
      period_seconds: 'Report period in seconds'
    )

    deliver :email do
      template { event.user_id.blank? ? :daily_report : nil }
      system_template { event.user_id.blank? }
      vars { respond_to?(:report_vars) ? report_vars : {} }
      options do
        if event.user_id.blank?
          { language: VpsAdmin::API::Events::Core.system_report_language(event) }
        else
          {}
        end
      end
    end
  end

  event 'lifetime.expiration_warning',
        label: 'Expiration warning',
        category: 'account',
        severity: :warning,
        default_routed: true do
    parameters(
      object: 'Expiring object type',
      object_id: 'Expiring object ID',
      object_label: 'Expiring object label',
      state: 'Object lifecycle state',
      expiration_date: 'Expiration date',
      remind_after_date: 'Reminder silence date',
      expires_in_days: 'Days until expiration',
      expired_days_ago: 'Days since expiration',
      expires_in_a_day: 'Whether expiration is within a day'
    )

    deliver :email do
      template :expiration_warning
      params do
        {
          object: VpsAdmin::API::Events::Core.param(event, 'object'),
          state: VpsAdmin::API::Events::Core.param(event, 'state')
        }
      end
      vars { VpsAdmin::API::Events::Core.expiration_warning_email_vars(event) }
    end
  end

  %w[security_advisory.announced security_advisory.updated].each do |event_name|
    event event_name,
          label: event_name.end_with?('announced') ? 'Security advisory announced' : 'Security advisory updated',
          category: 'security',
          severity: :warning,
          default_routed: true do
      params = {
        advisory_id: 'Security advisory ID',
        advisory_name: 'Security advisory name',
        cves: 'CVE identifiers',
        state: 'Security advisory state',
        published_at: 'Publication time',
        affected_vps_count: 'Affected VPS count',
        affected_vpses: 'Affected VPS sample'
      }
      if event_name.end_with?('updated')
        params = {
          advisory_id: 'Security advisory ID',
          advisory_name: 'Security advisory name',
          update_id: 'Security advisory update ID',
          update_summary: 'Update summary'
        }.merge(params.except(:advisory_id, :advisory_name))
      end
      parameters(params)

      deliver :email do
        template(event_name.end_with?('announced') ? :security_advisory_user_announce : :security_advisory_user_update)
        vars { VpsAdmin::API::Events::Core.security_advisory_email_vars(event) }
      end
    end
  end

  event 'vps.incident_report',
        label: 'Incident report',
        category: 'incidents',
        severity: :warning,
        default_routed: true do
    parameters(
      subject: 'Report subject',
      text: 'Report text',
      codename: 'Report codename',
      ip_addr: 'Affected IP address',
      vps_id: 'Affected VPS ID'
    )

    deliver :email do
      template :vps_incident_report
      vars { VpsAdmin::API::Events::Core.incident_email_vars(event) }
    end
  end

  event 'incident_report.reply',
        label: 'Incident report reply',
        category: 'incidents',
        severity: :info,
        default_routed: true do
    parameters(
      from_email: 'Reply sender e-mail',
      recipient_emails: 'Reply recipient e-mail addresses',
      in_reply_to_message_id: 'Original Message-ID',
      references_message_id: 'References Message-ID',
      incident_count: 'Created incident report count',
      user_count: 'Affected user count',
      vps_count: 'Affected VPS count',
      incident_ids: 'Created incident report ID sample',
      text: 'Reply text'
    )

    deliver :email do
      custom_target do
        recipients = Array(VpsAdmin::API::Events::Core.param(event, 'recipient_emails'))
                     .map(&:to_s)
                     .reject(&:blank?)
        recipients.join(',') if event.user_id.blank? && recipients.present?
      end
      custom_body { VpsAdmin::API::Events::Core.param(event, 'text') if event.user_id.blank? }
      custom_options do
        next {} if event.user_id.present?

        {
          from: VpsAdmin::API::Events::Core.param(event, 'from_email'),
          in_reply_to: VpsAdmin::API::Events::Core.param(event, 'in_reply_to_message_id'),
          references: VpsAdmin::API::Events::Core.param(event, 'references_message_id')
        }.compact
      end
    end
  end

  event 'vps.oom_report',
        label: 'OOM report',
        category: 'vps',
        severity: :warning,
        default_routed: true do
    parameters(
      stage: 'OOM event stage',
      cgroup: 'Affected cgroup',
      cgroups: 'Affected cgroups',
      count: 'OOM count',
      killed_name: 'Killed process',
      report_count: 'Report count',
      selected_report_count: 'Selected report count',
      selected_oom_count: 'Selected OOM count'
    )

    deliver :email do
      template :vps_oom_report
      vars { VpsAdmin::API::Events::Core.oom_report_email_vars(event) }
    end
  end

  event 'vps.oom_prevention',
        label: 'OOM prevention',
        category: 'vps',
        severity: :critical,
        default_routed: true do
    parameters(
      action: 'Prevention action',
      reason: 'Reason',
      ooms_in_period: 'OOM count in period',
      period_seconds: 'Period in seconds'
    )

    deliver :email do
      template :vps_oom_prevention
      vars { VpsAdmin::API::Events::Core.oom_prevention_email_vars(event) }
    end
  end

  {
    'vps.suspended' => ['VPS suspended', :warning, :vps_suspend],
    'vps.resumed' => ['VPS resumed', :info, :vps_resume]
  }.each do |event_name, (label, severity, template_name)|
    event event_name,
          label:,
          category: 'vps',
          severity:,
          default_routed: true do
      parameters(
        vps_id: 'VPS ID',
        vps_hostname: 'VPS hostname',
        state: 'Lifecycle state',
        reason: 'Lifecycle reason',
        expiration_date: 'Expiration date',
        changed_by_id: 'User ID that changed the state',
        changed_by_name: 'User name that changed the state'
      )

      deliver :email do
        template template_name
        vars { VpsAdmin::API::Events::Core.vps_state_email_vars(event) }
      end
    end
  end

  event 'vps.resources_changed',
        label: 'VPS resources changed',
        category: 'vps',
        severity: :info,
        default_routed: true do
    parameters(
      vps_id: 'VPS ID',
      vps_hostname: 'VPS hostname',
      cpu: 'CPU cores',
      cpu_limit: 'CPU limit',
      memory: 'Memory in MiB',
      swap: 'Swap in MiB',
      reason: 'Change reason',
      admin_id: 'Admin user ID',
      admin_name: 'Admin name'
    )

    deliver :email do
      template :vps_resources_change
      vars { VpsAdmin::API::Events::Core.vps_resources_email_vars(event) }
    end
  end

  event 'vps.dns_resolver_changed',
        label: 'VPS DNS resolver changed',
        category: 'vps',
        severity: :info,
        default_routed: true do
    parameters(
      vps_id: 'VPS ID',
      vps_hostname: 'VPS hostname',
      old_dns_resolver_id: 'Previous DNS resolver ID',
      old_dns_resolver_label: 'Previous DNS resolver label',
      old_dns_resolver_addrs: 'Previous DNS resolver addresses',
      new_dns_resolver_id: 'New DNS resolver ID',
      new_dns_resolver_label: 'New DNS resolver label',
      new_dns_resolver_addrs: 'New DNS resolver addresses'
    )

    deliver :email do
      template :vps_dns_resolver_change
      vars { VpsAdmin::API::Events::Core.vps_dns_resolver_email_vars(event) }
    end
  end

  {
    'vps.network_disabled' => ['VPS network disabled', :warning, :vps_network_disabled],
    'vps.network_enabled' => ['VPS network enabled', :info, :vps_network_enabled]
  }.each do |event_name, (label, severity, template_name)|
    event event_name,
          label:,
          category: 'vps',
          severity:,
          default_routed: true do
      parameters(
        vps_id: 'VPS ID',
        vps_hostname: 'VPS hostname',
        reason: 'Disable/enable reason'
      )

      deliver :email do
        template template_name
        vars { VpsAdmin::API::Events::Core.vps_network_email_vars(event) }
      end
    end
  end

  {
    'vps.stopped_over_quota' => ['VPS stopped over quota', :warning, :vps_stopped_over_quota],
    'vps.dataset_expanded' => ['VPS dataset expanded', :info, :vps_dataset_expanded],
    'vps.dataset_shrunk' => ['VPS dataset shrunk', :info, :vps_dataset_shrunk]
  }.each do |event_name, (label, severity, template_name)|
    event event_name,
          label:,
          category: 'vps',
          severity:,
          default_routed: true do
      parameters(
        vps_id: 'VPS ID',
        vps_hostname: 'VPS hostname',
        dataset_id: 'Dataset ID',
        dataset_full_name: 'Dataset name',
        dataset_refquota: 'Dataset refquota',
        dataset_referenced: 'Dataset referenced space',
        expansion_id: 'Dataset expansion ID',
        original_refquota: 'Original refquota',
        added_space: 'Added space',
        expansion_count: 'Expansion count',
        over_refquota_seconds: 'Time over quota in seconds',
        max_over_refquota_seconds: 'Maximum time over quota in seconds',
        enable_shrink: 'Whether automatic shrink is enabled'
      )

      deliver :email do
        template template_name
        vars { VpsAdmin::API::Events::Core.vps_dataset_expansion_email_vars(event) }
      end
    end
  end

  event 'snapshot.download_ready',
        label: 'Snapshot download ready',
        category: 'storage',
        severity: :info,
        default_routed: true do
    parameters(
      download_id: 'Snapshot download ID',
      snapshot_id: 'Snapshot ID',
      snapshot_name: 'Snapshot name',
      dataset_id: 'Dataset ID',
      dataset_full_name: 'Dataset name',
      file_name: 'Download file name',
      format: 'Download format',
      expiration_date: 'Download expiration date'
    )

    deliver :email do
      template :snapshot_download_ready
      vars { VpsAdmin::API::Events::Core.snapshot_download_email_vars(event) }
    end
  end

  %w[dataset.migration_begun dataset.migration_finished].each do |event_name|
    event event_name,
          label: event_name.end_with?('begun') ? 'Dataset migration begun' : 'Dataset migration finished',
          category: 'storage',
          severity: event_name.end_with?('begun') ? :warning : :info,
          default_routed: true do
      argument :vpses, type: Array, optional: true

      parameters(
        dataset_id: 'Dataset ID',
        dataset_full_name: 'Dataset name',
        user_id: 'Dataset owner user ID',
        user_login: 'Dataset owner login',
        user_name: 'Dataset owner name',
        src_pool_id: 'Source pool ID',
        src_pool_filesystem: 'Source pool filesystem',
        dst_pool_id: 'Destination pool ID',
        dst_pool_filesystem: 'Destination pool filesystem',
        export_count: 'Export count',
        affected_vps_count: 'Affected VPS count',
        affected_vpses: 'Affected VPS sample',
        restart_vps: 'Whether affected VPSes are restarted',
        maintenance_window: 'Whether a maintenance window is used',
        custom_window: 'Whether a custom maintenance window is used',
        finish_weekday: 'Maintenance window weekday',
        finish_minutes: 'Maintenance window minute',
        reason: 'Migration reason'
      )

      deliver :email do
        template(event_name.end_with?('begun') ? :dataset_migration_begun : :dataset_migration_finished)
        vars do
          VpsAdmin::API::Events::Core.dataset_migration_email_vars(
            event,
            vpses: respond_to?(:vpses) ? vpses : nil
          )
        end
      end
    end
  end

  {
    'vps.migration_planned' => ['VPS migration planned', :warning, :vps_migration_planned],
    'vps.migration_begun' => ['VPS migration begun', :warning, :vps_migration_begun],
    'vps.migration_finished' => ['VPS migration finished', :info, :vps_migration_finished]
  }.each do |event_name, (label, severity, template_name)|
    event event_name,
          label:,
          category: 'vps',
          severity:,
          default_routed: true do
      parameters(
        migration_id: 'Migration ID',
        vps_id: 'VPS ID',
        vps_hostname: 'VPS hostname',
        src_node_id: 'Source node ID',
        src_node_domain_name: 'Source node domain name',
        dst_node_id: 'Destination node ID',
        dst_node_domain_name: 'Destination node domain name',
        maintenance_window: 'Whether a maintenance window is used',
        custom_window: 'Whether a custom maintenance window is used',
        finish_weekday: 'Maintenance window weekday',
        finish_minutes: 'Maintenance window minute',
        reason: 'Migration reason'
      )

      deliver :email do
        template template_name
        vars { VpsAdmin::API::Events::Core.vps_migration_email_vars(event) }
      end
    end
  end

  event 'vps.replaced',
        label: 'VPS replaced',
        category: 'vps',
        severity: :warning,
        default_routed: true do
    parameters(
      vps_id: 'VPS ID',
      vps_hostname: 'VPS hostname',
      original_vps_id: 'Original VPS ID',
      original_vps_hostname: 'Original VPS hostname',
      new_vps_id: 'New VPS ID',
      new_vps_hostname: 'New VPS hostname',
      reason: 'Replacement reason'
    )

    deliver :email do
      template :vps_replaced
      vars { VpsAdmin::API::Events::Core.vps_replaced_email_vars(event) }
    end
  end
end
