require 'json'
require 'time'

module VpsAdmin::API
  module Events
    EVALUATION_TIMEOUT = 0.5
    DELIVERY_LABEL_LIMIT = 255
    PARAMETER_SAMPLE_LIMIT = 30
    FALLBACK_COLLECTION_LIMIT = 100

    Type = Struct.new(
      :name,
      :label,
      :category,
      :severity,
      :parameters,
      :email_template
    )

    RequestInfo = Struct.new(:ip)
    UserInfo = Struct.new(:id, :login, :full_name)
    VpsInfo = Struct.new(:id, :hostname, :user)
    ObjectStateInfo = Struct.new(:state, :reason, :expiration_date, :user)
    NodeInfo = Struct.new(:id, :domain_name)
    PoolInfo = Struct.new(:id, :filesystem)
    DnsResolverInfo = Struct.new(:id, :label, :addrs)
    DatasetInfo = Struct.new(:id, :full_name, :refquota, :referenced, :user)
    DatasetExpansionInfo = Struct.new(
      :id,
      :original_refquota,
      :added_space,
      :expansion_count,
      :over_refquota_seconds,
      :max_over_refquota_seconds,
      :enable_shrink
    )
    SnapshotInfo = Struct.new(:id, :name, :dataset)
    SnapshotDownloadInfo = Struct.new(:id, :file_name, :expiration_date, :user, :snapshot)
    VpsMigrationInfo = Struct.new(:id, :maintenance_window)

    DeliveryPlan = Struct.new(
      :action,
      :target_kind,
      :target_value,
      :target_label,
      :template_name,
      :event_route,
      :notification_receiver,
      :notification_receiver_action,
      :state,
      :error_summary,
      :next_attempt_at
    )

    RouteResult = Struct.new(
      :routing_state,
      :matched_event_route,
      :deliveries
    ) do
      def suppressed_by_mute?
        routing_state == 'suppressed' &&
          deliveries.any? do |delivery|
            receiver = delivery.notification_receiver
            receiver&.enabled? && receiver.mute?
          end
      end
    end

    @types = {}

    module_function

    def register(name, label:, category:, severity: :info, parameters: {},
                 email_template: nil)
      @types[name.to_s] = Type.new(
        name: name.to_s,
        label:,
        category: category.to_s,
        severity: severity.to_s,
        parameters:,
        email_template: email_template&.to_s
      )
    end

    def types
      @types.values.sort_by(&:name)
    end

    def type_for(name)
      @types[name.to_s]
    end

    def type_labels
      types.to_h { |type| [type.name, type.label] }
    end

    def field_labels(event_type: nil)
      EventRouteMatcher.field_labels(event_type:)
    end

    def email_template_name_for(event, action = nil)
      (action&.template_name.presence || type_for(event.event_type)&.email_template)&.to_sym
    end

    def email_template_params_for(event)
      case event.event_type
      when 'lifetime.expiration_warning'
        params = event.parameters || {}
        {
          object: params['object'] || params[:object],
          state: params['state'] || params[:state]
        }
      end
    end

    def email_template_options_for(event, delivery)
      opts = {
        user: event.user,
        vars: email_vars_for(event)
      }
      template_params = email_template_params_for(event)
      opts[:params] = template_params if template_params

      if delivery.custom_target_kind?
        opts[:to] = email_target_addresses(event, delivery)
        opts[:include_default_recipients] = false
        opts[:include_template_recipients] = false
      end

      opts
    end

    def email_custom_options_for(event, delivery)
      {
        user: event.user,
        from: MailTemplates.default_from,
        to: email_target_addresses(event, delivery),
        subject: event.subject,
        text_plain: custom_email_body(event)
      }
    end

    def email_target_addresses(event, delivery)
      if delivery.default_recipient_target_kind?
        address = delivery.target_value.presence
        address = nil if address == 'default'
        address ||= event.user&.email
        raise ArgumentError, 'event has no user e-mail recipient' if address.blank?

        return [address]
      end

      addresses = delivery.target_value.to_s.split(',').map(&:strip).reject(&:blank?)
      raise ArgumentError, 'e-mail delivery has no recipient address' if addresses.empty?

      addresses
    end

    def email_vars_for(event)
      return event.runtime_email_vars if event.runtime_email_vars

      case event.event_type
      when 'user.created'
        user_email_vars(event)
      when 'user.suspended', 'user.soft_deleted', 'user.resumed', 'user.revived'
        user_state_email_vars(event)
      when 'user.new_login'
        user_new_login_email_vars(event)
      when 'user.new_token'
        user_new_token_email_vars(event)
      when 'user.totp_recovery_code_used'
        user_totp_recovery_email_vars(event)
      when 'user.failed_logins'
        user_failed_logins_email_vars(event)
      when 'lifetime.expiration_warning'
        expiration_warning_email_vars(event)
      when 'security_advisory.announced', 'security_advisory.updated'
        security_advisory_email_vars(event)
      when 'vps.incident_report'
        incident_email_vars(event)
      when 'vps.oom_report'
        oom_report_email_vars(event)
      when 'vps.oom_prevention'
        oom_prevention_email_vars(event)
      when 'vps.suspended', 'vps.resumed'
        vps_state_email_vars(event)
      when 'vps.resources_changed'
        vps_resources_email_vars(event)
      when 'vps.dns_resolver_changed'
        vps_dns_resolver_email_vars(event)
      when 'vps.network_disabled', 'vps.network_enabled'
        vps_network_email_vars(event)
      when 'vps.stopped_over_quota'
        vps_stopped_over_quota_email_vars(event)
      when 'vps.dataset_expanded', 'vps.dataset_shrunk'
        vps_dataset_expansion_email_vars(event)
      when 'snapshot.download_ready'
        snapshot_download_email_vars(event)
      when 'dataset.migration_begun', 'dataset.migration_finished'
        dataset_migration_email_vars(event)
      when 'vps.migration_planned', 'vps.migration_begun', 'vps.migration_finished'
        vps_migration_email_vars(event)
      when 'vps.replaced'
        vps_replaced_email_vars(event)
      else
        {
          event:,
          user: event.user,
          parameters: event.parameters || {}
        }
      end
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

    def user_new_login_email_vars(event)
      session = user_session_source(event)
      authorization = find_from_parameters(event, ::Oauth2Authorization, 'authorization_id')
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
      params = event.parameters || {}
      request_ip = params['request_ip'] || params[:request_ip]
      totp_device = user_totp_device_source(event) ||
                    find_from_parameters(event, ::UserTotpDevice, 'totp_device_id')

      {
        user: event.user,
        totp_device:,
        request: request_ip.present? ? RequestInfo.new(request_ip) : nil,
        time: parse_time(params['used_at'] || params[:used_at]) || event.created_at
      }
    end

    def user_failed_logins_email_vars(event)
      {
        user: event.user,
        attempt_groups: failed_login_groups(event)
      }
    end

    def expiration_warning_email_vars(event)
      params = event.parameters || {}
      object = expiration_warning_object(event)
      object_key = params['object'] || params[:object]
      state = object_state_from_parameters(event)
      expires_in_days = numeric_param(params['expires_in_days'] || params[:expires_in_days])
      expired_days_ago = numeric_param(params['expired_days_ago'] || params[:expired_days_ago])

      ret = {
        base_url: ::SysConfig.get(:webui, :base_url),
        user: event.user,
        object:,
        state:,
        expires_in_days:,
        expired_days_ago:,
        expires_in_a_day: truthy_param(params['expires_in_a_day'] || params[:expires_in_a_day])
      }
      ret[object_key] = object if object_key.present?
      ret
    end

    def user_source(event)
      source = event.source
      return unless source.is_a?(::User)
      return if event.user_id.present? && source.id != event.user_id

      source
    end

    def object_state_source(event)
      event.source if event.source.is_a?(::ObjectState)
    end

    def object_state_from_parameters(event)
      params = event.parameters || {}

      ObjectStateInfo.new(
        state: params['state'] || params[:state],
        reason: params['reason'] || params[:reason],
        expiration_date: parse_time(params['expiration_date'] || params[:expiration_date]),
        user: user_info_from_parameters(params, 'changed_by')
      )
    end

    def user_session_source(event)
      user_owned_source(event, ::UserSession)
    end

    def user_totp_device_source(event)
      user_owned_source(event, ::UserTotpDevice)
    end

    def find_from_parameters(event, model, key)
      value = (event.parameters || {})[key] || (event.parameters || {})[key.to_sym]
      return if value.blank?

      scope = model.all
      if event.user_id.present? && model.column_names.include?('user_id')
        scope = scope.where(user_id: event.user_id)
      end

      scope.find_by(id: value)
    end

    def failed_login_groups(event)
      params = event.parameters || {}
      group_ids = Array(params['attempt_group_ids'] || params[:attempt_group_ids])
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

    def user_owned_source(event, model)
      source = event.source
      return unless source.is_a?(model)
      return if event.user_id.present? && source.user_id != event.user_id

      source
    end

    def expiration_warning_object(event)
      params = event.parameters || {}

      case params['object'] || params[:object]
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

    def incident_email_vars(event)
      incident = event.source if event.source.is_a?(::IncidentReport)
      raise ArgumentError, 'incident report source is missing' unless incident

      {
        base_url: ::SysConfig.get(:webui, :base_url),
        user: incident.user,
        vps: incident.vps,
        incident:
      }
    end

    def oom_report_email_vars(event)
      params = event.parameters || {}
      selected_reports = oom_reports_from_ids(
        event,
        params['selected_report_ids'] || params[:selected_report_ids]
      )
      reports = oom_reports_from_batch(event, selected_reports)

      raise ArgumentError, 'OOM report parameters are missing report ids' if reports.empty?

      selected_reports = reports.first(30) if selected_reports.empty?

      {
        base_url: ::SysConfig.get(:webui, :base_url),
        vps: event.vps || reports.first.vps,
        all_oom_reports: reports,
        all_oom_count: params['oom_count'] || params[:oom_count] || reports.sum(&:count),
        selected_oom_reports: selected_reports,
        selected_oom_count: params['selected_oom_count'] || params[:selected_oom_count] || selected_reports.sum(&:count)
      }
    end

    def oom_prevention_email_vars(event)
      params = event.parameters || {}
      vps = event.vps

      raise ArgumentError, 'OOM prevention VPS is missing' unless vps

      {
        base_url: ::SysConfig.get(:webui, :base_url),
        vps:,
        action: (params['action'] || params[:action])&.to_sym,
        ooms_in_period: params['ooms_in_period'] || params[:ooms_in_period],
        period_seconds: params['period_seconds'] || params[:period_seconds]
      }
    end

    def vps_state_email_vars(event)
      {
        vps: required_vps(event),
        state: object_state_source(event) || object_state_from_parameters(event)
      }
    end

    def vps_resources_email_vars(event)
      params = event.parameters || {}

      {
        vps: required_vps(event),
        admin: user_info_from_parameters(params, 'admin'),
        reason: params['reason'] || params[:reason]
      }
    end

    def vps_dns_resolver_email_vars(event)
      {
        vps: required_vps(event),
        old_dns_resolver: dns_resolver_from_parameters(event, 'old'),
        new_dns_resolver: dns_resolver_from_parameters(event, 'new')
      }
    end

    def vps_network_email_vars(event)
      params = event.parameters || {}

      {
        user: event.user,
        vps: required_vps(event),
        reason: params['reason'] || params[:reason] || ''
      }
    end

    def vps_stopped_over_quota_email_vars(event)
      vps_dataset_expansion_email_vars(event)
    end

    def vps_dataset_expansion_email_vars(event)
      expansion = dataset_expansion_source(event) || dataset_expansion_from_parameters(event)
      dataset = expansion.is_a?(::DatasetExpansion) ? expansion.dataset : dataset_from_parameters(event)

      {
        base_url: ::SysConfig.get(:webui, :base_url),
        vps: required_vps(event),
        expansion:,
        dataset:
      }
    end

    def snapshot_download_email_vars(event)
      download = snapshot_download_source(event)
      return { base_url: ::SysConfig.get(:webui, :base_url), dl: download } if download

      params = event.parameters || {}
      dataset = dataset_from_parameters(event)
      snapshot = SnapshotInfo.new(
        id: params['snapshot_id'] || params[:snapshot_id],
        name: params['snapshot_name'] || params[:snapshot_name],
        dataset:
      )
      download = SnapshotDownloadInfo.new(
        id: params['download_id'] || params[:download_id],
        file_name: params['file_name'] || params[:file_name],
        expiration_date: parse_time(params['expiration_date'] || params[:expiration_date]),
        user: event.user,
        snapshot:
      )

      {
        base_url: ::SysConfig.get(:webui, :base_url),
        dl: download
      }
    end

    def dataset_migration_email_vars(event)
      params = event.parameters || {}
      dataset = dataset_source(event) || dataset_from_parameters(event)

      {
        dataset:,
        src_pool: pool_info_from_parameters(params, 'src'),
        dst_pool: pool_info_from_parameters(params, 'dst'),
        exports: Array.new(bounded_collection_count(params['export_count'] || params[:export_count])),
        export_mounts: [],
        vpses: vps_infos_from_parameters(event),
        restart_vps: truthy_param(params['restart_vps'] || params[:restart_vps]),
        maintenance_window: truthy_param(params['maintenance_window'] || params[:maintenance_window]),
        maintenance_windows: [],
        custom_window: truthy_param(params['custom_window'] || params[:custom_window]),
        finish_weekday: params['finish_weekday'] || params[:finish_weekday],
        finish_minutes: params['finish_minutes'] || params[:finish_minutes],
        reason: params['reason'] || params[:reason]
      }
    end

    def vps_migration_email_vars(event)
      params = event.parameters || {}

      {
        m: vps_migration_source(event) || VpsMigrationInfo.new(
          id: params['migration_id'] || params[:migration_id],
          maintenance_window: truthy_param(params['maintenance_window'] || params[:maintenance_window])
        ),
        vps: required_vps(event),
        src_node: node_info_from_parameters(params, 'src'),
        dst_node: node_info_from_parameters(params, 'dst'),
        maintenance_window: truthy_param(params['maintenance_window'] || params[:maintenance_window]),
        maintenance_windows: [],
        custom_window: truthy_param(params['custom_window'] || params[:custom_window]),
        finish_weekday: params['finish_weekday'] || params[:finish_weekday],
        finish_minutes: params['finish_minutes'] || params[:finish_minutes],
        reason: params['reason'] || params[:reason]
      }
    end

    def vps_replaced_email_vars(event)
      params = event.parameters || {}
      new_vps = secondary_vps_source(event) ||
                find_vps_from_parameters(event, 'new_vps_id') ||
                vps_info_from_parameters(event, 'new')

      {
        original_vps: required_vps(event),
        new_vps:,
        reason: params['reason'] || params[:reason]
      }
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
        webui_url: webui_url
      }
    end

    def required_vps(event)
      vps = event.vps
      raise ArgumentError, "#{event.event_type} VPS is missing" unless vps

      if event.user_id.present? && vps.user_id != event.user_id
        raise ArgumentError, "#{event.event_type} VPS does not belong to event user"
      end

      vps
    end

    def dns_resolver_from_parameters(event, prefix)
      params = event.parameters || {}

      DnsResolverInfo.new(
        id: params["#{prefix}_dns_resolver_id"] || params[:"#{prefix}_dns_resolver_id"],
        label: params["#{prefix}_dns_resolver_label"] || params[:"#{prefix}_dns_resolver_label"],
        addrs: params["#{prefix}_dns_resolver_addrs"] || params[:"#{prefix}_dns_resolver_addrs"] || ''
      )
    end

    def user_info_from_parameters(params, prefix)
      login = params["#{prefix}_login"] || params[:"#{prefix}_login"]
      full_name = params["#{prefix}_name"] || params[:"#{prefix}_name"] || login
      return if full_name.blank?

      UserInfo.new(
        id: params["#{prefix}_id"] || params[:"#{prefix}_id"],
        login: login || full_name,
        full_name:
      )
    end

    def dataset_expansion_source(event)
      source = event.source
      return unless source.is_a?(::DatasetExpansion)
      return if event.vps_id.present? && source.vps_id != event.vps_id
      return if event.user_id.present? && source.vps.user_id != event.user_id

      source
    end

    def snapshot_download_source(event)
      source = event.source
      return unless source.is_a?(::SnapshotDownload)
      return if event.user_id.present? && source.user_id != event.user_id

      source
    end

    def dataset_source(event)
      source = event.source
      return unless source.is_a?(::Dataset)
      return if event.user_id.present? && source.user_id != event.user_id

      source
    end

    def vps_migration_source(event)
      source = event.source
      return unless source.is_a?(::VpsMigration)
      return if event.user_id.present? && source.vps.user_id != event.user_id

      source
    end

    def secondary_vps_source(event)
      source = event.source
      return unless source.is_a?(::Vps)
      return if event.vps_id.present? && source.id == event.vps_id
      return if event.user_id.present? && source.user_id != event.user_id

      source
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
      params = event.parameters || {}
      advisory_id = params['advisory_id'] || params[:advisory_id]
      return if advisory_id.blank?

      ::SecurityAdvisory.visible_to(event.user).find_by(id: advisory_id)
    end

    def security_advisory_update_from_parameters(event, advisory)
      params = event.parameters || {}
      update_id = params['update_id'] || params[:update_id]
      return if update_id.blank?

      advisory.security_advisory_updates.find_by(id: update_id)
    end

    def security_advisory_vpses_for(advisory, user)
      scope = advisory.security_advisory_vpses.includes(:vps, :node).order(:vps_id)
      return scope.none unless user

      scope.where(user:)
    end

    def dataset_expansion_from_parameters(event)
      params = event.parameters || {}

      DatasetExpansionInfo.new(
        id: params['expansion_id'] || params[:expansion_id],
        original_refquota: (params['original_refquota'] || params[:original_refquota]).to_i,
        added_space: (params['added_space'] || params[:added_space]).to_i,
        expansion_count: (params['expansion_count'] || params[:expansion_count]).to_i,
        over_refquota_seconds: (params['over_refquota_seconds'] || params[:over_refquota_seconds]).to_i,
        max_over_refquota_seconds: (params['max_over_refquota_seconds'] || params[:max_over_refquota_seconds]).to_i,
        enable_shrink: params['enable_shrink'] || params[:enable_shrink]
      )
    end

    def dataset_from_parameters(event)
      params = event.parameters || {}

      DatasetInfo.new(
        id: params['dataset_id'] || params[:dataset_id],
        full_name: params['dataset_full_name'] || params[:dataset_full_name],
        refquota: (params['dataset_refquota'] || params[:dataset_refquota]).to_i,
        referenced: (params['dataset_referenced'] || params[:dataset_referenced]).to_i,
        user: event.user || user_info_from_parameters(params, 'user')
      )
    end

    def node_info_from_parameters(params, prefix)
      NodeInfo.new(
        id: params["#{prefix}_node_id"] || params[:"#{prefix}_node_id"],
        domain_name: params["#{prefix}_node_domain_name"] || params[:"#{prefix}_node_domain_name"]
      )
    end

    def pool_info_from_parameters(params, prefix)
      PoolInfo.new(
        id: params["#{prefix}_pool_id"] || params[:"#{prefix}_pool_id"],
        filesystem: params["#{prefix}_pool_filesystem"] || params[:"#{prefix}_pool_filesystem"]
      )
    end

    def vps_infos_from_parameters(event)
      params = event.parameters || {}

      Array(params['affected_vpses'] || params[:affected_vpses]).map do |item|
        data = item.respond_to?(:to_h) ? item.to_h : {}
        VpsInfo.new(
          id: data['id'] || data[:id],
          hostname: data['hostname'] || data[:hostname],
          user: event.user
        )
      end
    end

    def vps_info_from_parameters(event, prefix)
      params = event.parameters || {}
      hostname = params["#{prefix}_vps_hostname"] || params[:"#{prefix}_vps_hostname"]
      return if hostname.blank?

      VpsInfo.new(
        id: params["#{prefix}_vps_id"] || params[:"#{prefix}_vps_id"],
        hostname:,
        user: event.user
      )
    end

    def find_vps_from_parameters(event, key)
      value = (event.parameters || {})[key] || (event.parameters || {})[key.to_sym]
      return if value.blank?

      scope = ::Vps.including_deleted
      scope = scope.where(user_id: event.user_id) if event.user_id.present?
      scope.find_by(id: value)
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

      [count, FALLBACK_COLLECTION_LIMIT].min
    end

    def oom_reports_from_ids(event, ids)
      ids = Array(ids).map(&:to_i).uniq
      return [] if ids.empty?

      reports = oom_report_scope(event).where(id: ids).to_a.index_by(&:id)
      ids.filter_map { |id| reports[id] }
    end

    def oom_reports_from_batch(event, selected_reports)
      params = event.parameters || {}
      batch_time = parse_batch_time(params['batch_reported_at'] || params[:batch_reported_at])

      return selected_reports if batch_time.nil?

      scope = oom_report_scope(event).order('oom_reports.created_at')
      last_reported_id = params['last_reported_id'] || params[:last_reported_id]
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

    def parse_batch_time(value)
      return if value.blank?

      Time.iso8601(value.to_s)
    rescue ArgumentError
      nil
    end

    def parse_time(value)
      parse_batch_time(value)
    end

    def custom_email_body(event)
      ret = [
        event.summary.presence,
        "Event type: #{event.event_type}",
        "Severity: #{event.severity}",
        event.vps && "VPS: ##{event.vps.id} #{event.vps.hostname}",
        event.ip_addr && "IP address: #{event.ip_addr}",
        "Parameters:\n#{JSON.pretty_generate(event.parameters || {})}"
      ].compact

      ret.join("\n\n")
    end

    def webui_url
      (::SysConfig.get(:webui, :base_url) || '').chomp('/')
    rescue StandardError
      ''
    end

    def parameter_field?(field)
      return false unless field.to_s.start_with?('parameters.')

      name = field.to_s.delete_prefix('parameters.')
      types.any? { |type| type.parameters.has_key?(name.to_sym) || type.parameters.has_key?(name) }
    end

    def plan(event_type, user: nil, vps: nil, subject: nil, summary: nil,
             parameters: {}, severity: nil, category: nil, ip_addr: nil)
      type = type_for(event_type)
      if user && vps && vps.user_id != user.id
        raise ArgumentError, 'user and VPS owner do not match'
      end

      owner = user || vps&.user
      event = ::Event.new(
        user: owner,
        vps:,
        event_type: event_type.to_s,
        category: category || type&.category || 'general',
        severity: severity || type&.severity || 'info',
        subject: subject || type&.label || event_type.to_s,
        summary:,
        parameters: parameters || {},
        ip_addr:
      )

      Router.new(event).plan
    end

    def emit!(event_type, user: nil, vps: nil, source: nil, source_class: nil,
              source_id: nil, subject: nil, summary: nil, parameters: {},
              severity: nil, category: nil, ip_addr: nil, route: true,
              email_vars: nil)
      type = type_for(event_type)
      if user && vps && vps.user_id != user.id
        raise ArgumentError, 'user and VPS owner do not match'
      end

      owner = user || vps&.user

      event = ::Event.create!(
        user: owner,
        vps:,
        event_type: event_type.to_s,
        category: category || type&.category,
        severity: severity || type&.severity,
        subject: subject || type&.label,
        summary:,
        parameters: parameters || {},
        source_class: source_class || source&.class&.name,
        source_id: source_id || source&.id,
        ip_addr:
      )
      event.runtime_email_vars = email_vars if email_vars

      route!(event) if route

      event
    end

    def route!(event)
      Router.new(event).route!
    end

    class Router
      attr_reader :event

      def initialize(event)
        @event = event
      end

      def route!
        event.class.transaction do
          event.lock!
          event.event_deliveries.delete_all
          result = plan

          event.update!(
            routing_state: result.routing_state,
            matched_event_route: result.matched_event_route
          )

          result.deliveries.each do |delivery|
            create_delivery!(delivery)
          end
        end

        event
      end

      def plan
        ensure_default_routes
        plan_route
      end

      protected

      def ensure_default_routes
        return unless event.user

        ::NotificationReceiver.ensure_defaults_for!(event.user)
      end

      def plan_route
        deadline = monotonic_time + EVALUATION_TIMEOUT
        deliveries = []
        first_matched_route = nil

        child_routes(nil).each do |route|
          break if deadline_expired?(deadline)
          next unless route.matches?(event, deadline:)

          first_matched_route ||= route
          deliveries.concat(process_route(route, deadline))

          break unless route.continue?
        end

        if deliveries.empty?
          deliveries = [skipped_delivery(nil, nil, nil, 'no route matched the event')]
        end

        first_delivery_route = deliveries.map(&:event_route).compact.first

        RouteResult.new(
          routing_state: routing_state_for(deliveries),
          matched_event_route: first_delivery_route || first_matched_route,
          deliveries: deduplicate(deliveries)
        )
      end

      def process_route(route, deadline)
        ::EventRoute.increment_counter(:hit_count, route.id)

        deliveries = []
        matched_child = false

        child_routes(route.id).each do |child|
          break if deadline_expired?(deadline)
          next unless child.matches?(event, deadline:)

          matched_child = true
          deliveries.concat(process_route(child, deadline))

          break unless child.continue?
        end

        return deliveries if matched_child

        deliveries_for_route(route)
      end

      def child_routes(parent_id)
        routes_by_parent[parent_id] || []
      end

      def routes_by_parent
        @routes_by_parent ||= if event.user
                                event.user.event_routes
                                     .where(enabled: true)
                                     .includes(:event_route_matchers, notification_receiver: :notification_receiver_actions)
                                     .order(:position, :id)
                                     .to_a
                                     .group_by(&:parent_id)
                              else
                                {}
                              end
      end

      def deliveries_for_route(route)
        receiver = route.notification_receiver

        return [skipped_delivery(route, nil, nil, 'route has no receiver')] unless receiver

        unless receiver.enabled?
          return [skipped_delivery(route, receiver, nil, 'receiver is disabled')]
        end

        if receiver.mute?
          return [skipped_delivery(route, receiver, nil, 'receiver does not notify')]
        end

        actions = receiver.notification_receiver_actions.select(&:enabled?)

        if actions.empty?
          return [skipped_delivery(route, receiver, nil, 'receiver has no enabled actions')]
        end

        actions.map { |receiver_action| delivery_from_receiver_action(route, receiver, receiver_action) }
      end

      def delivery_from_receiver_action(route, receiver, receiver_action)
        unless receiver_action.deliverable?
          reason = receiver_action.enabled? ? 'receiver action is not verified' : 'receiver action is disabled'
          return skipped_delivery(route, receiver, receiver_action, reason)
        end

        case receiver_action.action
        when 'email'
          email_delivery(route, receiver, receiver_action)
        when 'telegram'
          telegram_delivery(route, receiver, receiver_action)
        when 'webhook'
          webhook_delivery(route, receiver, receiver_action)
        else
          skipped_delivery(route, receiver, receiver_action, 'unknown receiver action')
        end
      end

      def email_delivery(route, receiver, receiver_action)
        if receiver_action.default_recipient_target_kind?
          if event.user.nil?
            return skipped_delivery(route, receiver, receiver_action, 'event has no user')
          end

          return build_delivery(
            route,
            receiver,
            receiver_action,
            target_value: 'default',
            target_label: 'Default recipient'
          )
        end

        build_delivery(
          route,
          receiver,
          receiver_action,
          target_value: receiver_action.target_value,
          target_label: delivery_label(receiver_action.target_value)
        )
      end

      def telegram_delivery(route, receiver, receiver_action)
        return skipped_delivery(route, receiver, receiver_action, 'Telegram chat is not linked') if receiver_action.target_value.blank?

        build_delivery(
          route,
          receiver,
          receiver_action,
          target_value: receiver_action.target_value,
          target_label: receiver_action.display_target
        )
      end

      def webhook_delivery(route, receiver, receiver_action)
        return skipped_delivery(route, receiver, receiver_action, 'webhook URL is not configured') if receiver_action.target_value.blank?

        build_delivery(
          route,
          receiver,
          receiver_action,
          target_value: receiver_action.target_value,
          target_label: receiver_action.label,
          state: 'queued',
          next_attempt_at: Time.now
        )
      end

      def build_delivery(route, receiver, receiver_action, target_value:, target_label:, state: 'planned', next_attempt_at: nil)
        DeliveryPlan.new(
          action: receiver_action.action,
          target_kind: receiver_action.target_kind,
          target_value:,
          target_label: delivery_label(target_label),
          template_name: delivery_template_name(receiver_action),
          event_route: route,
          notification_receiver: receiver,
          notification_receiver_action: receiver_action,
          state:,
          next_attempt_at:
        )
      end

      def skipped_delivery(route, receiver, receiver_action, reason)
        DeliveryPlan.new(
          action: receiver_action&.action || 'email',
          target_kind: receiver_action&.target_kind || 'default_recipient',
          target_value: receiver_action&.target_value,
          target_label: delivery_label(receiver_action&.display_target || receiver&.label),
          template_name: receiver_action&.template_name,
          event_route: route,
          notification_receiver: receiver,
          notification_receiver_action: receiver_action,
          state: 'skipped',
          error_summary: reason
        )
      end

      def delivery_label(label)
        return if label.nil?

        label.to_s[0, DELIVERY_LABEL_LIMIT]
      end

      def delivery_template_name(receiver_action)
        return receiver_action.template_name if receiver_action.template_name.present?
        return unless receiver_action.email_action?

        VpsAdmin::API::Events.email_template_name_for(event, receiver_action)
      end

      def routing_state_for(deliveries)
        deliveries.any? { |delivery| delivery.state != 'skipped' } ? 'routed' : 'suppressed'
      end

      def deduplicate(deliveries)
        deliveries.uniq do |delivery|
          deduplication_key(delivery)
        end
      end

      def deduplication_key(delivery)
        if delivery.state == 'skipped'
          return [
            delivery.state,
            delivery.event_route&.id,
            delivery.notification_receiver&.id,
            delivery.notification_receiver_action&.id,
            delivery.error_summary
          ]
        end

        [
          delivery.action,
          delivery.target_kind,
          delivery.target_value,
          delivery.template_name,
          delivery.state
        ]
      end

      def create_delivery!(delivery)
        event.event_deliveries.create!(
          event_route: delivery.event_route,
          notification_receiver: delivery.notification_receiver,
          notification_receiver_action: delivery.notification_receiver_action,
          action: delivery.action,
          target_kind: delivery.target_kind,
          target_value: delivery.target_value,
          target_label: delivery.target_label,
          template_name: delivery.template_name,
          state: delivery.state,
          error_summary: delivery.error_summary,
          next_attempt_at: delivery.next_attempt_at
        )
      end

      def monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def deadline_expired?(deadline)
        monotonic_time >= deadline
      end
    end

    register(
      'user.created',
      label: 'User account created',
      category: 'account',
      severity: :info,
      email_template: :user_create,
      parameters: {
        login: 'User login',
        email: 'User e-mail',
        level: 'User level',
        object_state: 'Initial account state',
        create_vps: 'Whether an initial VPS was requested',
        active: 'Whether the account was activated'
      }
    )

    register(
      'user.suspended',
      label: 'User account suspended',
      category: 'account',
      severity: :warning,
      email_template: :user_suspend,
      parameters: {
        state: 'Lifecycle state',
        reason: 'Lifecycle reason',
        expiration_date: 'Expiration date'
      }
    )

    register(
      'user.soft_deleted',
      label: 'User account disabled',
      category: 'account',
      severity: :warning,
      email_template: :user_soft_delete,
      parameters: {
        state: 'Lifecycle state',
        reason: 'Lifecycle reason',
        expiration_date: 'Expiration date'
      }
    )

    register(
      'user.resumed',
      label: 'User account resumed',
      category: 'account',
      severity: :info,
      email_template: :user_resume,
      parameters: {
        state: 'Lifecycle state',
        reason: 'Lifecycle reason',
        expiration_date: 'Expiration date'
      }
    )

    register(
      'user.revived',
      label: 'User account restored',
      category: 'account',
      severity: :info,
      email_template: :user_revive,
      parameters: {
        state: 'Lifecycle state',
        reason: 'Lifecycle reason',
        expiration_date: 'Expiration date'
      }
    )

    register(
      'user.new_login',
      label: 'New sign-in',
      category: 'security',
      severity: :warning,
      email_template: :user_new_login,
      parameters: {
        auth_type: 'Authentication type',
        client_ip_addr: 'Client IP address',
        api_ip_addr: 'API IP address',
        client_version: 'Client version',
        user_agent: 'User agent',
        user_device_id: 'User device ID',
        authorization_id: 'OAuth authorization ID',
        oauth2_client_id: 'OAuth client ID'
      }
    )

    register(
      'user.new_token',
      label: 'New access token',
      category: 'security',
      severity: :warning,
      email_template: :user_new_token,
      parameters: {
        auth_type: 'Authentication type',
        client_ip_addr: 'Client IP address',
        api_ip_addr: 'API IP address',
        client_version: 'Client version',
        scope: 'Token scope',
        token_lifetime: 'Token lifetime',
        label: 'Token label'
      }
    )

    register(
      'user.totp_recovery_code_used',
      label: 'TOTP recovery code used',
      category: 'security',
      severity: :critical,
      email_template: :user_totp_recovery_code_used,
      parameters: {
        totp_device_id: 'TOTP device ID',
        totp_device_label: 'TOTP device label',
        request_ip: 'Request IP address',
        used_at: 'Recovery time'
      }
    )

    register(
      'user.failed_logins',
      label: 'Failed sign-in report',
      category: 'security',
      severity: :warning,
      email_template: :user_failed_logins,
      parameters: {
        attempt_count: 'Failed attempt count',
        group_count: 'Attempt group count',
        attempt_group_ids: 'Failed attempt IDs grouped by similarity',
        ip_addrs: 'Client IP addresses',
        auth_types: 'Authentication types',
        reasons: 'Failure reasons'
      }
    )

    register(
      'user.test_notification',
      label: 'Test notification',
      category: 'test',
      severity: :info,
      parameters: {
        note: 'Test note'
      }
    )

    register(
      'lifetime.expiration_warning',
      label: 'Expiration warning',
      category: 'account',
      severity: :warning,
      email_template: :expiration_warning,
      parameters: {
        object: 'Expiring object type',
        object_id: 'Expiring object ID',
        object_label: 'Expiring object label',
        state: 'Object lifecycle state',
        expiration_date: 'Expiration date',
        remind_after_date: 'Reminder silence date',
        expires_in_days: 'Days until expiration',
        expired_days_ago: 'Days since expiration',
        expires_in_a_day: 'Whether expiration is within a day'
      }
    )

    register(
      'security_advisory.announced',
      label: 'Security advisory announced',
      category: 'security',
      severity: :warning,
      email_template: :security_advisory_user_announce,
      parameters: {
        advisory_id: 'Security advisory ID',
        advisory_name: 'Security advisory name',
        cves: 'CVE identifiers',
        state: 'Security advisory state',
        published_at: 'Publication time',
        affected_vps_count: 'Affected VPS count',
        affected_vpses: 'Affected VPS sample'
      }
    )

    register(
      'security_advisory.updated',
      label: 'Security advisory updated',
      category: 'security',
      severity: :warning,
      email_template: :security_advisory_user_update,
      parameters: {
        advisory_id: 'Security advisory ID',
        advisory_name: 'Security advisory name',
        update_id: 'Security advisory update ID',
        update_summary: 'Update summary',
        cves: 'CVE identifiers',
        state: 'Security advisory state',
        published_at: 'Publication time',
        affected_vps_count: 'Affected VPS count',
        affected_vpses: 'Affected VPS sample'
      }
    )

    register(
      'vps.incident_report',
      label: 'Incident report',
      category: 'incidents',
      severity: :warning,
      email_template: :vps_incident_report,
      parameters: {
        subject: 'Report subject',
        text: 'Report text',
        codename: 'Report codename',
        ip_addr: 'Affected IP address',
        vps_id: 'Affected VPS ID'
      }
    )

    register(
      'vps.oom_report',
      label: 'OOM report',
      category: 'vps',
      severity: :warning,
      email_template: :vps_oom_report,
      parameters: {
        stage: 'OOM event stage',
        cgroup: 'Affected cgroup',
        cgroups: 'Affected cgroups',
        count: 'OOM count',
        killed_name: 'Killed process',
        report_count: 'Report count',
        selected_report_count: 'Selected report count',
        selected_oom_count: 'Selected OOM count'
      }
    )

    register(
      'vps.oom_prevention',
      label: 'OOM prevention',
      category: 'vps',
      severity: :critical,
      email_template: :vps_oom_prevention,
      parameters: {
        action: 'Prevention action',
        reason: 'Reason',
        ooms_in_period: 'OOM count in period',
        period_seconds: 'Period in seconds'
      }
    )

    register(
      'vps.suspended',
      label: 'VPS suspended',
      category: 'vps',
      severity: :warning,
      email_template: :vps_suspend,
      parameters: {
        vps_id: 'VPS ID',
        vps_hostname: 'VPS hostname',
        state: 'Lifecycle state',
        reason: 'Lifecycle reason',
        expiration_date: 'Expiration date',
        changed_by_id: 'User ID that changed the state',
        changed_by_name: 'User name that changed the state'
      }
    )

    register(
      'vps.resumed',
      label: 'VPS resumed',
      category: 'vps',
      severity: :info,
      email_template: :vps_resume,
      parameters: {
        vps_id: 'VPS ID',
        vps_hostname: 'VPS hostname',
        state: 'Lifecycle state',
        reason: 'Lifecycle reason',
        expiration_date: 'Expiration date',
        changed_by_id: 'User ID that changed the state',
        changed_by_name: 'User name that changed the state'
      }
    )

    register(
      'vps.resources_changed',
      label: 'VPS resources changed',
      category: 'vps',
      severity: :info,
      email_template: :vps_resources_change,
      parameters: {
        vps_id: 'VPS ID',
        vps_hostname: 'VPS hostname',
        cpu: 'CPU cores',
        cpu_limit: 'CPU limit',
        memory: 'Memory in MiB',
        swap: 'Swap in MiB',
        reason: 'Change reason',
        admin_id: 'Admin user ID',
        admin_name: 'Admin name'
      }
    )

    register(
      'vps.dns_resolver_changed',
      label: 'VPS DNS resolver changed',
      category: 'vps',
      severity: :info,
      email_template: :vps_dns_resolver_change,
      parameters: {
        vps_id: 'VPS ID',
        vps_hostname: 'VPS hostname',
        old_dns_resolver_id: 'Previous DNS resolver ID',
        old_dns_resolver_label: 'Previous DNS resolver label',
        old_dns_resolver_addrs: 'Previous DNS resolver addresses',
        new_dns_resolver_id: 'New DNS resolver ID',
        new_dns_resolver_label: 'New DNS resolver label',
        new_dns_resolver_addrs: 'New DNS resolver addresses'
      }
    )

    register(
      'vps.network_disabled',
      label: 'VPS network disabled',
      category: 'vps',
      severity: :warning,
      email_template: :vps_network_disabled,
      parameters: {
        vps_id: 'VPS ID',
        vps_hostname: 'VPS hostname',
        reason: 'Disable reason'
      }
    )

    register(
      'vps.network_enabled',
      label: 'VPS network enabled',
      category: 'vps',
      severity: :info,
      email_template: :vps_network_enabled,
      parameters: {
        vps_id: 'VPS ID',
        vps_hostname: 'VPS hostname',
        reason: 'Enable reason'
      }
    )

    register(
      'vps.stopped_over_quota',
      label: 'VPS stopped over quota',
      category: 'vps',
      severity: :warning,
      email_template: :vps_stopped_over_quota,
      parameters: {
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
      }
    )

    register(
      'vps.dataset_expanded',
      label: 'VPS dataset expanded',
      category: 'vps',
      severity: :info,
      email_template: :vps_dataset_expanded,
      parameters: {
        vps_id: 'VPS ID',
        vps_hostname: 'VPS hostname',
        dataset_id: 'Dataset ID',
        dataset_full_name: 'Dataset name',
        dataset_refquota: 'Dataset refquota',
        dataset_referenced: 'Dataset referenced space',
        expansion_id: 'Dataset expansion ID',
        original_refquota: 'Original refquota',
        added_space: 'Added space',
        expansion_count: 'Expansion count'
      }
    )

    register(
      'vps.dataset_shrunk',
      label: 'VPS dataset shrunk',
      category: 'vps',
      severity: :info,
      email_template: :vps_dataset_shrunk,
      parameters: {
        vps_id: 'VPS ID',
        vps_hostname: 'VPS hostname',
        dataset_id: 'Dataset ID',
        dataset_full_name: 'Dataset name',
        dataset_refquota: 'Dataset refquota',
        dataset_referenced: 'Dataset referenced space',
        expansion_id: 'Dataset expansion ID',
        original_refquota: 'Original refquota',
        added_space: 'Added space',
        expansion_count: 'Expansion count'
      }
    )

    register(
      'snapshot.download_ready',
      label: 'Snapshot download ready',
      category: 'storage',
      severity: :info,
      email_template: :snapshot_download_ready,
      parameters: {
        download_id: 'Snapshot download ID',
        snapshot_id: 'Snapshot ID',
        snapshot_name: 'Snapshot name',
        dataset_id: 'Dataset ID',
        dataset_full_name: 'Dataset name',
        file_name: 'Download file name',
        format: 'Download format',
        expiration_date: 'Download expiration date'
      }
    )

    register(
      'dataset.migration_begun',
      label: 'Dataset migration begun',
      category: 'storage',
      severity: :warning,
      email_template: :dataset_migration_begun,
      parameters: {
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
      }
    )

    register(
      'dataset.migration_finished',
      label: 'Dataset migration finished',
      category: 'storage',
      severity: :info,
      email_template: :dataset_migration_finished,
      parameters: {
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
      }
    )

    register(
      'vps.migration_planned',
      label: 'VPS migration planned',
      category: 'vps',
      severity: :warning,
      email_template: :vps_migration_planned,
      parameters: {
        migration_id: 'Migration ID',
        vps_id: 'VPS ID',
        vps_hostname: 'VPS hostname',
        src_node_id: 'Source node ID',
        src_node_domain_name: 'Source node domain name',
        dst_node_id: 'Destination node ID',
        dst_node_domain_name: 'Destination node domain name',
        maintenance_window: 'Whether a maintenance window is used'
      }
    )

    register(
      'vps.migration_begun',
      label: 'VPS migration begun',
      category: 'vps',
      severity: :warning,
      email_template: :vps_migration_begun,
      parameters: {
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
      }
    )

    register(
      'vps.migration_finished',
      label: 'VPS migration finished',
      category: 'vps',
      severity: :info,
      email_template: :vps_migration_finished,
      parameters: {
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
      }
    )

    register(
      'vps.replaced',
      label: 'VPS replaced',
      category: 'vps',
      severity: :warning,
      email_template: :vps_replaced,
      parameters: {
        vps_id: 'VPS ID',
        vps_hostname: 'VPS hostname',
        original_vps_id: 'Original VPS ID',
        original_vps_hostname: 'Original VPS hostname',
        new_vps_id: 'New VPS ID',
        new_vps_hostname: 'New VPS hostname',
        reason: 'Replacement reason'
      }
    )
  end
end
