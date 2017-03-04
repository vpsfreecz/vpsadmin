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

      # If the outage is staged, update original translations too
      if outage.state == 'staged' \
          && (attrs[:state].nil? || attrs[:state] == ::Outage.states[:staged])
          translations.each do |lang, attrs|
            begin
              outage.outage_translations(true).find_by!(language: lang).update!(attrs)

            rescue ActiveRecord::RecordNotFound
              tr = ::OutageTranslation.new(attrs)
              tr.outage = self
              tr.language = lang
              tr.save!
            end
          end

        outage.load_translations
        return outage
      end

      outage.load_translations
      outage.set_affected_vpses if attrs[:state] == ::Outage.states[:announced]

      return outage unless opts[:send_mail]

      # Generic mail announcement
      send_mail('generic', nil, outage, report, attrs, last_report)

      # Mail affected users directly
      outage.affected_users.each do |u|
        next unless u.mailer_enabled

        send_mail('user', u, outage, report, attrs, last_report)
      end

      outage
    end

    protected
    def send_mail(role, u, outage, report, attrs, last_report)
      event = {
          ::Outage.states[:announced] => 'announce',
          ::Outage.states[:cancelled] => 'cancel',
          ::Outage.states[:closed] => 'closed',
      }
      msg_id = message_id(
          attrs[:state] == ::Outage.states[:announced] ? :announce : :update,
          outage, report, u
      )

      if last_report
        in_reply_to = message_id(:announce, outage, last_report, u)

      else
        in_reply_to = nil
      end

      send_first(
          [
              [
                  :outage_report_role_event,
                  {role: role, event: event[attrs[:state]] || 'update'},
              ],
              [
                  :outage_report_role_event,
                  {role: role, event: 'update'},
              ],
              [
                  :outage_report_role,
                  {role: role},
              ],
          ],
          user: u,
          language: u ? nil : ::Language.take, # TODO: configurable language
          message_id: msg_id,
          in_reply_to: in_reply_to,
          references: in_reply_to,
          vars: {
              outage: outage,
              o: outage,
              update: report,
              user: u,
              vpses: u && ::Vps.joins(:outage_vpses).where(
                  outage_vpses: {outage_id: outage.id},
                  vpses: {user_id: u.id},
              ),
          }
      )
    end

    def send_first(templates, opts)
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
          user_id: user ? user.id : 0,
      }
    end
  end
end
