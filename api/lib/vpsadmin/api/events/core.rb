module VpsAdmin::API::Events::Core
  module_function

  def param(event, name)
    params = event.payload || {}
    params[name.to_s] || params[name.to_sym]
  end

  def params(event)
    event.payload || {}
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
    fields(
      login: { description: 'Login of the created user account', type: :string },
      email: { description: 'E-mail address set on the created account', type: :string },
      level: { description: 'Numeric user level assigned during creation', type: :integer },
      object_state: { description: 'Initial lifecycle state of the account', type: :string },
      create_vps: { description: 'Whether an initial VPS was requested', type: :boolean },
      active: { description: 'Whether the account was activated immediately', type: :boolean }
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
      fields(
        state: { description: 'Account lifecycle state after the change', type: :string },
        reason: { description: 'Operator-provided reason for the lifecycle change', type: :string },
        expiration_date: { description: 'Date when the lifecycle state expires', type: :datetime }
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
    fields(
      auth_type: { description: 'Authentication method used to create the token', type: :string },
      client_ip_addr: { description: 'Client IP address reported by the API client', type: :string },
      api_ip_addr: { description: 'IP address observed by the vpsAdmin API', type: :string },
      client_version: { description: 'Version string reported by the API client', type: :string },
      scope: { description: 'Access scope granted to the token', type: :string },
      token_lifetime: { description: 'Token lifetime requested by the user session', type: :string },
      label: { description: 'User-visible token label', type: :string }
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
    fields(
      totp_device_id: { description: 'ID of the TOTP device whose recovery code was used', type: :integer },
      totp_device_label: { description: 'User-visible label of the affected TOTP device', type: :string },
      request_ip: { description: 'IP address that submitted the recovery code', type: :string },
      used_at: { description: 'Time when the recovery code was accepted', type: :datetime }
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
    fields(
      attempt_count: { description: 'Total number of failed sign-in attempts in the report', type: :integer },
      group_count: { description: 'Number of attempt groups included in the report', type: :integer },
      ip_addrs: { description: 'Client IP addresses observed in failed attempts', type: :string_list },
      auth_types: { description: 'Authentication methods used in failed attempts', type: :string_list },
      reasons: { description: 'Failure reasons reported by authentication', type: :string_list }
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
    fields(
      note: { description: 'Free-form note supplied when creating the test event', type: :string }
    )
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

    field(:auth_type, 'Authentication method used for the sign-in', type: :string) do
      session.auth_type
    end
    field(:client_ip_addr, 'Client IP address reported by the API client', type: :string) do
      session.client_ip_addr
    end
    field(:api_ip_addr, 'IP address observed by the vpsAdmin API', type: :string) do
      session.api_ip_addr
    end
    field(:client_version, 'Version string reported by the API client', type: :string) do
      session.client_version
    end
    field(:user_agent, 'HTTP User-Agent header used by the client', type: :string) do
      session.user_agent_string
    end
    field(:user_device_id, 'ID of the remembered user device used for sign-in', type: :integer) do
      authorization.user_device&.id
    end
    field(:authorization_id, 'ID of the OAuth authorization used for sign-in', type: :integer) do
      authorization.id
    end
    field(:oauth2_client_id, 'ID of the OAuth client application', type: :integer) do
      authorization.oauth2_client_id
    end

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
    fields(
      chain_id: { description: 'ID of the transaction chain whose state changed', type: :integer },
      chain_name: { description: 'Internal transaction chain name', type: :string },
      chain_label: { description: 'User-visible transaction chain label', type: :string },
      previous_state: { description: 'Transaction chain state before the change', type: :string },
      state: { description: 'Transaction chain state after the change', type: :string },
      terminal: {
        description: 'Whether the chain reached a terminal state',
        type: :boolean
      },
      successful: {
        description: 'Whether the terminal state is successful',
        type: :boolean
      },
      failed: {
        description: 'Whether the terminal state is failed or fatal',
        type: :boolean
      },
      size: { description: 'Number of transactions in the chain', type: :integer },
      progress: { description: 'Number of transactions already finished', type: :integer },
      user_session_id: { description: 'ID of the user session that created the chain', type: :integer },
      concern_classes: { description: 'Classes of objects affected by the chain', type: :string_list },
      concern_object_ids: { description: 'IDs of objects affected by the chain', type: :integer_list },
      node_id: { description: 'ID of the node that reported the state change', type: :integer },
      node_name: { description: 'Domain name of the node that reported the state change', type: :string },
      changed_at: { description: 'Time when the chain state changed', type: :datetime },
      changed_at_timestamp: { description: 'Unix timestamp of the state change', type: :number }
    )
  end

  %w[dns.zone_transfer.failed dns.zone_transfer.recovered].each do |event_name|
    event event_name,
          label: event_name.end_with?('failed') ? 'DNS zone transfer failed' : 'DNS zone transfer recovered',
          category: 'dns',
          severity: event_name.end_with?('failed') ? :warning : :info,
          default_routed: false do
      fields(
        transfer_log_id: { description: 'ID of the DNS transfer log row', type: :integer },
        dns_zone_id: { description: 'ID of the DNS zone being transferred', type: :integer },
        dns_zone_name: { description: 'Name of the DNS zone being transferred', type: :string },
        dns_server_zone_id: { description: 'ID of the DNS server zone assignment', type: :integer },
        dns_server_id: { description: 'ID of the DNS server handling the transfer', type: :integer },
        dns_server_name: { description: 'Name of the DNS server handling the transfer', type: :string },
        node_id: { description: 'ID of the node hosting the DNS server', type: :integer },
        node_name: { description: 'Domain name of the node hosting the DNS server', type: :string },
        previous_status: { description: 'Transfer status before this event', type: :string },
        status: { description: 'Transfer status reported by the DNS server', type: :string },
        reason_code: { description: 'Machine-readable transfer failure reason', type: :string },
        reason: { description: 'Human-readable transfer failure reason', type: :string },
        primary_addr: { description: 'Primary DNS server address used for transfer', type: :string },
        serial: { description: 'DNS zone serial observed during transfer', type: :integer },
        message: { description: 'Additional transfer message', type: :string },
        event_at: { description: 'Time when the DNS transfer event happened', type: :datetime }
      )
    end
  end

  event 'system.daily_report',
        label: 'Daily report',
        category: 'system',
        severity: :info,
        default_routed: true do
    argument :report_vars, type: Hash, optional: true

    fields(
      language_id: { description: 'ID of the language used for the report', type: :integer },
      language_code: { description: 'Language code used for the report', type: :string },
      period_start: { description: 'Beginning of the report period', type: :datetime },
      period_end: { description: 'End of the report period', type: :datetime },
      period_seconds: { description: 'Length of the report period in seconds', type: :integer }
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
    fields(
      object: { description: 'Type of object whose lifecycle state expires', type: :string },
      object_id: { description: 'ID of the expiring object', type: :integer },
      object_label: { description: 'User-visible label of the expiring object', type: :string },
      state: { description: 'Lifecycle state that is about to expire or already expired', type: :string },
      expiration_date: { description: 'Time when the lifecycle state expires', type: :datetime },
      remind_after_date: { description: 'Time before which repeated reminders are suppressed', type: :datetime },
      expires_in_days: { description: 'Number of days until expiration', type: :number },
      expired_days_ago: { description: 'Number of days since expiration', type: :number },
      expires_in_a_day: { description: 'Whether expiration is within the next day', type: :boolean }
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
        advisory_id: { description: 'ID of the security advisory', type: :integer },
        advisory_name: { description: 'Name of the security advisory', type: :string },
        cves: { description: 'CVE identifiers mentioned by the advisory', type: :string_list },
        state: { description: 'Current lifecycle state of the advisory', type: :string },
        published_at: { description: 'Time when the advisory was published', type: :datetime },
        affected_vps_count: { description: 'Number of affected VPSes visible to the recipient', type: :integer },
        affected_vps_ids: { description: 'IDs of affected VPSes included in the payload sample', type: :integer_list },
        affected_vps_hostnames: { description: 'Hostnames of affected VPSes included in the payload sample', type: :string_list }
      }
      if event_name.end_with?('updated')
        params = {
          advisory_id: { description: 'ID of the security advisory', type: :integer },
          advisory_name: { description: 'Name of the security advisory', type: :string },
          update_id: { description: 'ID of the advisory update', type: :integer },
          update_summary: { description: 'Summary of the advisory update', type: :string }
        }.merge(params.except(:advisory_id, :advisory_name))
      end
      fields(params)

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
    fields(
      subject: { description: 'Subject line received with the incident report', type: :string },
      text: { description: 'Body text received with the incident report', type: :string },
      codename: { description: 'Incident report codename assigned by vpsAdmin', type: :string },
      ip_addr: { description: 'IP address mentioned by the incident report', type: :string },
      vps_id: { description: 'ID of the VPS associated with the incident report', type: :integer }
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
    fields(
      from_email: { description: 'E-mail address that sent the reply', type: :string },
      recipient_emails: { description: 'Recipient e-mail addresses parsed from the reply', type: :string_list },
      in_reply_to_message_id: { description: 'Message-ID referenced by the reply', type: :string },
      references_message_id: { description: 'References header from the reply', type: :string },
      incident_count: { description: 'Number of incident reports matched by the reply', type: :integer },
      user_count: { description: 'Number of users affected by the reply', type: :integer },
      vps_count: { description: 'Number of VPSes affected by the reply', type: :integer },
      incident_ids: { description: 'IDs of incident reports matched by the reply', type: :integer_list },
      text: { description: 'Reply body text', type: :string }
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
    fields(
      vps_id: { description: 'ID of the VPS affected by the OOM report', type: :integer },
      vps_hostname: { description: 'Hostname of the VPS affected by the OOM report', type: :string },
      stage: { description: 'Processing stage that emitted the OOM notification', type: :string },
      cgroup: { description: 'Primary affected cgroup path', type: :string },
      cgroups: { description: 'Affected cgroup paths included in the event', type: :string_list },
      count: { description: 'Number of OOM reports in the selected group', type: :integer },
      killed_name: { description: 'Name of the process killed by the kernel', type: :string },
      report_count: { description: 'Number of raw reports considered for the event', type: :integer },
      selected_report_count: { description: 'Number of raw reports selected for notification', type: :integer },
      selected_oom_count: { description: 'Number of OOM kills represented by selected reports', type: :integer },
      selected_report_ids: { description: 'IDs of raw OOM reports selected for notification', type: :integer_list },
      last_reported_id: { description: 'Highest raw OOM report ID already processed', type: :integer },
      batch_reported_at: { description: 'Time when the OOM report batch was processed', type: :datetime }
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
    fields(
      vps_id: { description: 'ID of the VPS affected by OOM prevention', type: :integer },
      vps_hostname: { description: 'Hostname of the VPS affected by OOM prevention', type: :string },
      action: { description: 'Preventive action taken after repeated OOM reports', type: :string },
      reason: { description: 'Reason why the preventive action was taken', type: :string },
      ooms_in_period: { description: 'Number of OOM reports seen in the tracked period', type: :integer },
      period_seconds: { description: 'Length of the tracked period in seconds', type: :integer }
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
      fields(
        vps_id: { description: 'ID of the VPS whose lifecycle state changed', type: :integer },
        vps_hostname: { description: 'Hostname of the VPS whose lifecycle state changed', type: :string },
        state: { description: 'VPS lifecycle state after the change', type: :string },
        reason: { description: 'Operator-provided reason for the lifecycle change', type: :string },
        expiration_date: { description: 'Date when the lifecycle state expires', type: :datetime },
        changed_by_id: { description: 'ID of the user who changed the VPS lifecycle state', type: :integer },
        changed_by_name: { description: 'Name of the user who changed the VPS lifecycle state', type: :string }
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
    fields(
      vps_id: { description: 'ID of the VPS whose resources changed', type: :integer },
      vps_hostname: { description: 'Hostname of the VPS whose resources changed', type: :string },
      cpu: { description: 'CPU core count assigned to the VPS after the change', type: :integer },
      cpu_limit: { description: 'CPU limit assigned to the VPS after the change', type: :number },
      memory: { description: 'Memory limit assigned to the VPS after the change, in MiB', type: :integer },
      swap: { description: 'Swap limit assigned to the VPS after the change, in MiB', type: :integer },
      reason: { description: 'Operator-provided reason for the resource change', type: :string },
      admin_id: { description: 'ID of the admin who changed the resources', type: :integer },
      admin_name: { description: 'Name of the admin who changed the resources', type: :string }
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
    fields(
      vps_id: { description: 'ID of the VPS whose resolver changed', type: :integer },
      vps_hostname: { description: 'Hostname of the VPS whose resolver changed', type: :string },
      old_dns_resolver_id: { description: 'ID of the previous DNS resolver', type: :integer },
      old_dns_resolver_label: { description: 'Label of the previous DNS resolver', type: :string },
      old_dns_resolver_addrs: { description: 'Addresses configured on the previous DNS resolver', type: :string },
      new_dns_resolver_id: { description: 'ID of the new DNS resolver', type: :integer },
      new_dns_resolver_label: { description: 'Label of the new DNS resolver', type: :string },
      new_dns_resolver_addrs: { description: 'Addresses configured on the new DNS resolver', type: :string }
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
      fields(
        vps_id: { description: 'ID of the VPS whose network state changed', type: :integer },
        vps_hostname: { description: 'Hostname of the VPS whose network state changed', type: :string },
        reason: { description: 'Operator-provided reason for the network state change', type: :string }
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
      fields(
        vps_id: { description: 'ID of the VPS whose dataset quota changed', type: :integer },
        vps_hostname: { description: 'Hostname of the VPS whose dataset quota changed', type: :string },
        dataset_id: { description: 'ID of the dataset whose quota changed', type: :integer },
        dataset_full_name: { description: 'Full dataset name whose quota changed', type: :string },
        dataset_refquota: { description: 'Dataset refquota after the event, in bytes', type: :integer },
        dataset_referenced: { description: 'Referenced dataset space at the time of the event, in bytes', type: :integer },
        expansion_id: { description: 'ID of the dataset expansion record', type: :integer },
        original_refquota: { description: 'Dataset refquota before automatic expansion or shrink, in bytes', type: :integer },
        added_space: { description: 'Space added to the dataset refquota, in bytes', type: :integer },
        expansion_count: { description: 'Number of expansions represented by the event', type: :integer },
        over_refquota_seconds: { description: 'Time the dataset spent over quota, in seconds', type: :integer },
        max_over_refquota_seconds: { description: 'Maximum allowed time over quota before action, in seconds', type: :integer },
        enable_shrink: { description: 'Whether automatic shrink is enabled for the dataset', type: :boolean }
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
    fields(
      download_id: { description: 'ID of the prepared snapshot download', type: :integer },
      snapshot_id: { description: 'ID of the source snapshot', type: :integer },
      snapshot_name: { description: 'Name of the source snapshot', type: :string },
      dataset_id: { description: 'ID of the dataset that owns the snapshot', type: :integer },
      dataset_full_name: { description: 'Full name of the dataset that owns the snapshot', type: :string },
      file_name: { description: 'File name of the prepared download archive', type: :string },
      format: { description: 'Archive format of the prepared download', type: :string },
      expiration_date: { description: 'Time when the download link expires', type: :datetime }
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

      fields(
        dataset_id: { description: 'ID of the dataset being migrated', type: :integer },
        dataset_full_name: { description: 'Full name of the dataset being migrated', type: :string },
        user_id: { description: 'ID of the dataset owner', type: :integer },
        user_login: { description: 'Login of the dataset owner', type: :string },
        user_name: { description: 'Full name of the dataset owner', type: :string },
        src_pool_id: { description: 'ID of the source storage pool', type: :integer },
        src_pool_filesystem: { description: 'Filesystem name of the source storage pool', type: :string },
        dst_pool_id: { description: 'ID of the destination storage pool', type: :integer },
        dst_pool_filesystem: { description: 'Filesystem name of the destination storage pool', type: :string },
        export_count: { description: 'Number of exports affected by the migration', type: :integer },
        affected_vps_count: { description: 'Number of VPSes affected by the migration', type: :integer },
        affected_vps_ids: { description: 'IDs of VPSes affected by the migration', type: :integer_list },
        affected_vps_hostnames: { description: 'Hostnames of VPSes affected by the migration', type: :string_list },
        restart_vps: { description: 'Whether affected VPSes are restarted during migration', type: :boolean },
        maintenance_window: { description: 'Whether a maintenance window constrains the migration', type: :boolean },
        custom_window: { description: 'Whether a custom maintenance window is used', type: :boolean },
        finish_weekday: { description: 'Weekday when the maintenance window should finish', type: :integer },
        finish_minutes: { description: 'Minute of day when the maintenance window should finish', type: :integer },
        reason: { description: 'Operator-provided reason for the migration', type: :string }
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
      fields(
        migration_id: { description: 'ID of the VPS migration record', type: :integer },
        vps_id: { description: 'ID of the VPS being migrated', type: :integer },
        vps_hostname: { description: 'Hostname of the VPS being migrated', type: :string },
        src_node_id: { description: 'ID of the source node', type: :integer },
        src_node_domain_name: { description: 'Domain name of the source node', type: :string },
        dst_node_id: { description: 'ID of the destination node', type: :integer },
        dst_node_domain_name: { description: 'Domain name of the destination node', type: :string },
        maintenance_window: { description: 'Whether a maintenance window constrains the migration', type: :boolean },
        custom_window: { description: 'Whether a custom maintenance window is used', type: :boolean },
        finish_weekday: { description: 'Weekday when the maintenance window should finish', type: :integer },
        finish_minutes: { description: 'Minute of day when the maintenance window should finish', type: :integer },
        reason: { description: 'Operator-provided reason for the migration', type: :string }
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
    fields(
      vps_id: { description: 'ID of the VPS record that initiated replacement', type: :integer },
      vps_hostname: { description: 'Hostname of the VPS record that initiated replacement', type: :string },
      original_vps_id: { description: 'ID of the original VPS being replaced', type: :integer },
      original_vps_hostname: { description: 'Hostname of the original VPS being replaced', type: :string },
      new_vps_id: { description: 'ID of the newly created replacement VPS', type: :integer },
      new_vps_hostname: { description: 'Hostname of the newly created replacement VPS', type: :string },
      reason: { description: 'Operator-provided reason for the replacement', type: :string }
    )

    deliver :email do
      template :vps_replaced
      vars { VpsAdmin::API::Events::Core.vps_replaced_email_vars(event) }
    end
  end
end
