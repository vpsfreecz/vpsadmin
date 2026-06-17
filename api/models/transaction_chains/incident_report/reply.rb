module TransactionChains
  class IncidentReport::Reply < ::TransactionChain
    label 'Re: incident'

    # @param message [Mail::Message]
    # @param result [VpsAdmin::API::IncidentReports::Result]
    def link_chain(message, result)
      concerns(:affect, *result.incidents.map { |v| [v.vps.class.name, v.vps_id] }.uniq)

      user_cnt = result.incidents.map(&:user_id).uniq.length
      vps_cnt = result.incidents.map(&:vps_id).uniq.length
      text = reply_text(result, user_cnt, vps_cnt)

      event = route_event!(
        'incident_report.reply',
        subject: "Re: #{message.subject}",
        summary: text.truncate(::Event::MAX_SUMMARY_LENGTH),
        parameters: {
          from_email: result.reply[:from],
          recipient_emails: result.reply[:to],
          in_reply_to_message_id: message.message_id,
          references_message_id: message.message_id,
          incident_count: result.incidents.length,
          user_count: user_cnt,
          vps_count: vps_cnt,
          incident_ids: result.incidents.map(&:id).first(VpsAdmin::API::Events::PARAMETER_SAMPLE_LIMIT),
          text:
        }
      )
      ensure_email_deliveries_queued!(event)
    end

    protected

    def ensure_email_deliveries_queued!(event)
      failed = event
               .event_deliveries
               .where(action: 'email', state: 'failed')
               .order(:id)
               .first
      return unless failed

      raise "failed to queue incident report reply e-mail delivery: #{failed.error_summary}"
    end

    def reply_text(result, user_cnt, vps_cnt)
      if result.incidents.length > 100
        return "Created #{result.incidents.length} incident reports of #{user_cnt} users and #{vps_cnt} VPS\n"
      end

      text = "Created #{result.incidents.length} incident reports of #{user_cnt} users and #{vps_cnt} VPS:\n"

      result.incidents.each do |inc|
        text << "  Incident ##{inc.id}: user=#{inc.user_id} vps=#{inc.vps_id}\n"
      end

      text
    end
  end
end
