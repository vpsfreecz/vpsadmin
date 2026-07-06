module VpsAdmin::API::Plugins::OutageReports::Events
  OutageEntityInfo = Struct.new(:real_name)
  OutageHandlerInfo = Struct.new(:full_name)
  OutageInfo = Struct.new(
    :id,
    :outage_type,
    :state,
    :impact_type,
    :begins_at,
    :finished_at,
    :duration,
    :summary,
    :description,
    :entity_labels,
    :handler_names
  ) do
    def outage_type_label
      ::Outage.outage_type_label(outage_type)
    rescue NameError
      outage_type.to_s
    end

    def impact_type_label
      ::Outage.impact_type_label(impact_type)
    rescue NameError
      impact_type.to_s
    end

    def en_summary
      summary.to_s
    end

    def en_description
      description.to_s
    end

    def outage_entities
      Array(entity_labels).map { |label| OutageEntityInfo.new(label) }
    end

    def outage_handlers
      Array(handler_names).map { |name| OutageHandlerInfo.new(name) }
    end

    def to_hash
      {
        id:,
        type: outage_type,
        begins_at: begins_at&.iso8601,
        duration:,
        impact: impact_type,
        entities: outage_entities.map { |entity| { label: entity.real_name } },
        handlers: outage_handlers.map(&:full_name),
        translations: {
          en: {
            summary: en_summary,
            description: en_description
          }
        }
      }
    end
  end

  OutageUpdateInfo = Struct.new(
    :id,
    :outage,
    :state,
    :impact_type,
    :begins_at,
    :finished_at,
    :duration,
    :summary,
    :description,
    :reporter_name,
    :changes
  ) do
    def outage_type
      outage&.outage_type
    end

    def outage_type_label
      outage&.outage_type_label.to_s
    end

    def impact_type_label
      ::Outage.impact_type_label(impact_type)
    rescue NameError
      impact_type.to_s
    end

    def each_change
      Array(changes).each do |change|
        data = change.respond_to?(:to_h) ? change.to_h : {}
        field = data['field'] || data[:field]
        next if field.blank?

        yield(
          field.to_sym,
          normalize_change_value(field, data['from'] || data[:from]),
          normalize_change_value(field, data['to'] || data[:to])
        )
      end
    end

    def to_hash
      ret = {
        id:,
        changes: {},
        translations: {
          en: {
            summary: summary.to_s,
            description: description.to_s
          }
        }
      }

      each_change do |attr, old, new|
        key = attr == :impact_type ? :type : attr
        ret[:changes][key] = { from: old, to: new }
      end

      ret
    end

    def normalize_change_value(field, value)
      return if value.nil?
      return VpsAdmin::API::Events.parse_time(value) if %w[begins_at finished_at].include?(field.to_s)

      value
    end
  end

  module_function

  def param(event, name)
    params = event.payload || {}
    params[name.to_s] || params[name.to_sym]
  end

  def params(event)
    event.payload || {}
  end

  def outage_source(event)
    source = event.source
    outage = if source.is_a?(::Outage)
               source
             elsif source.is_a?(::OutageUpdate)
               source.outage
             end
    return unless outage && outage_visible_to_event_user?(event, outage)

    outage
  end

  def outage_from_parameters(event)
    outage_id = param(event, 'outage_id')
    outage = ::Outage.visible_to(event.user).find_by(id: outage_id) if outage_id.present?
    return outage if outage && outage_visible_to_event_user?(event, outage)

    OutageInfo.new(
      outage_id,
      param(event, 'outage_type'),
      param(event, 'state'),
      param(event, 'impact_type'),
      VpsAdmin::API::Events.parse_time(param(event, 'begins_at')),
      VpsAdmin::API::Events.parse_time(param(event, 'finished_at')),
      param(event, 'duration'),
      param(event, 'outage_summary') || param(event, 'summary'),
      param(event, 'outage_description') || param(event, 'description'),
      param(event, 'entity_labels') || [],
      param(event, 'handler_names') || []
    )
  end

  def outage_update_from_parameters(event, outage)
    OutageUpdateInfo.new(
      param(event, 'update_id'),
      outage,
      param(event, 'update_state') || param(event, 'state'),
      param(event, 'update_impact_type') || param(event, 'impact_type'),
      VpsAdmin::API::Events.parse_time(param(event, 'update_begins_at') || param(event, 'begins_at')),
      VpsAdmin::API::Events.parse_time(param(event, 'update_finished_at') || param(event, 'finished_at')),
      param(event, 'update_duration') || param(event, 'duration'),
      param(event, 'summary'),
      param(event, 'description'),
      param(event, 'reported_by_name'),
      param(event, 'changes') || []
    )
  end

  def outage_visible_to_event_user?(event, outage)
    return true if event.user_id.blank?

    outage.outage_users.where(user_id: event.user_id).exists?
  end

  def outage_vpses_for(outage, user, direct: nil)
    return unless user
    return [] unless outage.respond_to?(:outage_vpses)

    scope = outage.outage_vpses.where(user:)
    scope = scope.where(direct:) unless direct.nil?
    scope
  end

  def outage_exports_for(outage, user)
    return unless user
    return [] unless outage.respond_to?(:outage_exports)

    outage.outage_exports.where(user:)
  end

  def security_advisory_cves(outage)
    return [] unless outage.respond_to?(:outage_security_advisories)

    outage.outage_security_advisories
          .includes(security_advisory: :security_advisory_cves)
          .flat_map do |link|
      advisory = link.security_advisory

      advisory.security_advisory_cves.order(:cve_id).map do |cve|
        {
          advisory_id: advisory.id,
          advisory_name: advisory.name,
          cve_id: cve.cve_id,
          cve_url: cve.url
        }
      end
    end.uniq { |row| [row[:advisory_id], row[:cve_id]] }
  end

  def outage_email_vars(event)
    outage = outage_source(event) || outage_from_parameters(event)
    raise ArgumentError, 'outage is missing' unless outage

    update = outage_update_from_parameters(event, outage)
    user = event.user

    {
      outage:,
      o: outage,
      update:,
      user:,
      vpses: outage_vpses_for(outage, user),
      direct_vpses: outage_vpses_for(outage, user, direct: true),
      indirect_vpses: outage_vpses_for(outage, user, direct: false),
      exports: outage_exports_for(outage, user),
      security_advisory_cves: security_advisory_cves(outage),
      webui_url: VpsAdmin::API::Events.webui_url
    }
  end

  def outage_template_params(event)
    nil
  end

  def outage_template_choice(event)
    language = outage_system_event?(event) ? ::Language.take : event.user&.language
    choices = outage_template_candidates(event)

    choices.find do |name|
      VpsAdmin::API::Events.template_available?(name, nil, language)
    end || choices.first
  end

  def outage_template_candidates(event)
    audience = outage_system_event?(event) ? 'generic' : 'user'
    event_name = param(event, 'event') || 'update'

    [].tap do |ret|
      ret << "outage_report_#{audience}_#{event_name}"
      ret << "outage_report_#{audience}_update" unless event_name == 'update'
      ret << "outage_report_#{audience}"
    end.map(&:to_sym)
  end

  def outage_system_event?(event)
    event.user_id.blank?
  end

  def outage_template_options(event)
    ret = {
      message_id: param(event, 'mail_message_id')
    }.compact
    reply_to = param(event, 'reply_to_message_id')
    if reply_to
      ret[:in_reply_to] = reply_to
      ret[:references] = reply_to
    end
    ret[:language] = ::Language.take if outage_system_event?(event)
    ret
  end
end

VpsAdmin::API::Events.define owner: :outage_reports do
  {
    'outage.announced' => ['Outage announced', {
      entity_labels: { description: 'Labels of infrastructure entities affected by the outage', type: :string_list },
      handler_names: { description: 'Names of admins handling the outage', type: :string_list }
    }],
    'outage.updated' => ['Outage updated', {
      changed_fields: { description: 'Names of outage fields changed by the update', type: :string_list }
    }]
  }.each do |event_name, (label, event_fields)|
    event event_name,
          label:,
          category: 'outages',
          severity: :warning,
          roles: %i[account admin],
          default_routed: true do
      fields(
        {
          event: { description: 'Outage notification phase that produced the event', type: :string },
          outage_id: { description: 'ID of the outage report', type: :integer },
          update_id: { description: 'ID of the outage report update', type: :integer },
          outage_type: { description: 'Type of outage being reported', type: :string },
          state: { description: 'State of the outage after the update', type: :string },
          impact_type: { description: 'Kind of impact declared for the outage', type: :string },
          begins_at: { description: 'Time when the outage begins', type: :datetime },
          finished_at: { description: 'Time when the outage is expected or known to finish', type: :datetime },
          duration: { description: 'Expected outage duration in minutes', type: :integer },
          summary: { description: 'Summary text of the outage update', type: :string },
          description: { description: 'Detailed text of the outage update', type: :string },
          outage_summary: { description: 'Current summary text of the outage report', type: :string },
          outage_description: { description: 'Current detailed text of the outage report', type: :string },
          affected_user_id: { description: 'ID of the affected user for user-targeted events', type: :integer },
          affected_user_login: { description: 'Login of the affected user for user-targeted events', type: :string },
          affected_vps_count: { description: 'Number of VPSes affected by the outage', type: :integer },
          direct_vps_count: { description: 'Number of VPSes directly affected by the outage', type: :integer },
          indirect_vps_count: { description: 'Number of VPSes indirectly affected by the outage', type: :integer },
          affected_export_count: { description: 'Number of exports affected by the outage', type: :integer },
          cves: { description: 'CVE identifiers related to the outage', type: :string_list },
          reported_by_id: { description: 'ID of the admin who reported the update', type: :integer },
          reported_by_login: { description: 'Login of the admin who reported the update', type: :string },
          reported_by_name: { description: 'Full name of the admin who reported the update', type: :string }
        }.merge(event_fields)
      )

      deliver :email do
        template { VpsAdmin::API::Plugins::OutageReports::Events.outage_template_choice(event) }
        params { VpsAdmin::API::Plugins::OutageReports::Events.outage_template_params(event) }
        options { VpsAdmin::API::Plugins::OutageReports::Events.outage_template_options(event) }
        system_template { VpsAdmin::API::Plugins::OutageReports::Events.outage_system_event?(event) }
        vars { VpsAdmin::API::Plugins::OutageReports::Events.outage_email_vars(event) }
      end
    end
  end
end
