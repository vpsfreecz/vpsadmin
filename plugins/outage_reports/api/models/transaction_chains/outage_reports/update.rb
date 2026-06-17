module VpsAdmin::API::Plugins::OutageReports::TransactionChains
  class Update < ::TransactionChain
    label 'Update'
    allow_empty

    # @param outage [::Outage]
    # @param attrs [Hash] attributes of {::OutageReport}
    # @param translations [Hash] string; `{Language => {summary => '', description => ''}}`
    # @param opts [Hash]
    # @option opts [Boolean] send_mail
    def link_chain(outage, attrs, translations, opts)
      concerns(:affect, [outage.class.name, outage.id])
      last_report = outage.outage_updates.order('id DESC').take
      report = ::OutageUpdate.new

      attrs.each do |k, v|
        report.assign_attributes(k => v) if outage.send(k) != v
      end

      report.outage = outage
      report.reported_by = ::User.current
      report.save!

      translations.each do |lang, tr_attrs|
        tr = ::OutageTranslation.new(tr_attrs)
        tr.language = lang
        tr.outage_update = report
        tr.save!
      end

      report.origin = outage.attributes

      outage.assign_attributes(attrs)
      outage.save!

      # If the outage is staged, update original translations too
      if outage.state == 'staged' \
          && (attrs[:state].nil? || attrs[:state] == ::Outage.states[:staged])
        translations.each do |lang, tr_attrs|
          outage.outage_translations.find_by!(language: lang).update!(tr_attrs)
        rescue ActiveRecord::RecordNotFound
          tr = ::OutageTranslation.new(tr_attrs)
          tr.outage = outage
          tr.language = lang
          tr.save!
        end

        outage.load_translations
        return outage
      end

      outage.load_translations
      report.load_translations

      if attrs[:state] == ::Outage.states[:announced]
        outage.set_affected_vpses
        outage.set_affected_exports
        outage.set_affected_users
      end

      return outage unless opts[:send_mail]

      # Generic mail announcement
      route_outage_event!('generic', nil, outage, report, attrs, last_report)

      # Mail affected users directly
      outage.outage_users.includes(:user).joins(:user).where(
        users: {
          object_state: [
            ::User.object_states[:active],
            ::User.object_states[:suspended]
          ]
        }
      ).each do |ou|
        route_outage_event!('user', ou.user, outage, report, attrs, last_report)
      end

      outage
    end

    protected

    def route_outage_event!(role, user, outage, report, attrs, last_report)
      msg_id = message_id(
        attrs[:state] == ::Outage.states[:announced] ? :announce : :update,
        outage, report, user
      )

      in_reply_to = (message_id(:announce, outage, last_report, user) if last_report)

      route_event!(
        outage_event_type(attrs),
        user:,
        source: report,
        subject: outage_event_subject(outage, attrs),
        summary: report.summary,
        parameters: outage_event_parameters(
          role,
          user,
          outage,
          report,
          attrs,
          msg_id,
          in_reply_to
        ),
        email_vars: outage_email_vars(role, user, outage, report)
      )
    end

    def outage_event_type(attrs)
      attrs[:state] == ::Outage.states[:announced] ? 'outage.announced' : 'outage.updated'
    end

    def outage_mail_event(attrs)
      {
        ::Outage.states[:announced] => 'announce',
        ::Outage.states[:cancelled] => 'cancel',
        ::Outage.states[:resolved] => 'resolve'
      }.fetch(attrs[:state], 'update')
    end

    def outage_event_subject(outage, attrs)
      prefix = attrs[:state] == ::Outage.states[:announced] ? 'Outage report' : 'Outage update'
      "#{prefix} ##{outage.id}"
    end

    def outage_email_vars(role, user, outage, report)
      {
        outage:,
        o: outage,
        update: report,
        user:,
        vpses: user && outage.outage_vpses.where(user:),
        direct_vpses: user && outage.outage_vpses.where(user:, direct: true),
        indirect_vpses: user && outage.outage_vpses.where(user:, direct: false),
        exports: user && outage.outage_exports.where(user:),
        security_advisory_cves: security_advisory_cves(outage),
        webui_url: webui_url
      }
    end

    def outage_event_parameters(role, user, outage, report, attrs, msg_id, in_reply_to)
      {
        role:,
        event: outage_mail_event(attrs),
        outage_id: outage.id,
        update_id: report.id,
        outage_type: outage.outage_type,
        state: outage.state,
        impact_type: outage.impact_type,
        begins_at: outage.begins_at&.iso8601,
        finished_at: outage.finished_at&.iso8601,
        duration: outage.duration,
        summary: report.summary,
        description: bounded_text(report.description),
        outage_summary: outage_translation(outage, :summary),
        outage_description: bounded_text(outage_translation(outage, :description)),
        entity_labels: outage.outage_entities.map(&:real_name).first(VpsAdmin::API::Events::PARAMETER_SAMPLE_LIMIT),
        handler_names: outage.outage_handlers.map(&:full_name).first(VpsAdmin::API::Events::PARAMETER_SAMPLE_LIMIT),
        affected_user_id: user&.id,
        affected_user_login: user&.login,
        affected_vps_count: user && outage.outage_vpses.where(user:).count,
        direct_vps_count: user && outage.outage_vpses.where(user:, direct: true).count,
        indirect_vps_count: user && outage.outage_vpses.where(user:, direct: false).count,
        affected_export_count: user && outage.outage_exports.where(user:).count,
        cves: security_advisory_cves(outage).map { |cve| cve[:cve_id] },
        changes: outage_changes(report),
        reported_by_id: report.reported_by_id,
        reported_by_login: report.reported_by&.login,
        reported_by_name: report.reporter_name,
        mail_message_id: msg_id,
        reply_to_message_id: in_reply_to
      }.compact
    end

    def outage_changes(report)
      ret = []
      report.each_change do |field, from, to|
        ret << {
          field:,
          from: serialize_change_value(from),
          to: serialize_change_value(to)
        }
      end
      ret
    end

    def serialize_change_value(value)
      value.respond_to?(:iso8601) ? value.iso8601 : value
    end

    def bounded_text(value)
      value&.to_s&.slice(0, ::Event::MAX_SUMMARY_LENGTH)
    end

    def outage_translation(outage, attr)
      method_name = "en_#{attr}"
      return outage.public_send(method_name) if outage.respond_to?(method_name)

      outage.outage_translations.first&.public_send(attr).to_s
    end

    def security_advisory_cves(outage)
      VpsAdmin::API::Events.outage_security_advisory_cves(outage)
    end

    def webui_url
      (::SysConfig.get(:webui, :base_url) || '').chomp('/')
    rescue StandardError
      ''
    end

    def message_id(type, outage, update, user)
      format(::SysConfig.get(:plugin_outage_reports, :"#{type}_message_id"), outage_id: outage.id,
                                                                             update_id: update.id, user_id: user ? user.id : 0)
    end
  end
end
