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

      translations.each do |lang, attrs|
        tr = ::OutageTranslation.new(attrs)
        tr.language = lang
        tr.outage_update = report
        tr.save!
      end

      report.origin = outage.attributes

      outage.assign_attributes(attrs)
      outage.save!
      outage.load_translations
      return outage unless opts[:send_mail]

      event = {
          ::Outage.states[:announced] => 'announce',
          ::Outage.states[:cancelled] => 'cancel',
          ::Outage.states[:closed] => 'closed',
      }

      outage.affected_users.each do |u|
        msg_id = message_id(
            attrs[:state] == ::Outage.states[:announced] ? :announce : :update,
            outage, report, u
        )

        if last_report
          in_reply_to = message_id(:announce, outage, last_report, u)

        else
          in_reply_to = nil
        end

        send_mail(
            [
                [
                    :outage_report_event,
                    {event: event[attrs[:state]] || 'update'},
                ],
                [
                    :outage_report_event,
                    {event: 'update'},
                ],
                [
                    :outage_report,
                    {},
                ],
            ],
            user: u,
            message_id: msg_id,
            in_reply_to: in_reply_to,
            references: in_reply_to,
            vars: {
                outage: outage,
                o: outage,
                update: report,
                user: u,
                vpses: outage.affected_vpses(u),
            }
        ) if u.mailer_enabled
      end

      outage
    end

    protected
    def send_mail(templates, opts)
      templates.each do |id, params|
        begin
          args = {params: params}
          args.update(opts)

          mail(id, args)
          return

        rescue VpsAdmin::API::Exceptions::MailTemplateDoesNotExist
          next
        end
      end
    end

    def message_id(type, outage, update, user)
      ::SysConfig.get(:plugin_outage_reports, :"#{type}_message_id") % {
          outage_id: outage.id,
          update_id: update.id,
          user_id: user.id,
      }
    end
  end
end
