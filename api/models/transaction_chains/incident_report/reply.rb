module TransactionChains
  class IncidentReport::Reply < ::TransactionChain
    label 'Re: incident'

    # @param message [Mail::Message]
    # @param result [VpsAdmin::API::IncidentReports::Result]
    def link_chain(message, result)
      concerns(:affect, *result.incidents.map { |v| [v.vps.class.name, v.vps_id] }.uniq)

      user_cnt = result.incidents.map(&:user_id).uniq.length
      vps_cnt = result.incidents.map(&:vps_id).uniq.length
      text = ''

      if result.incidents.length <= 100
        text << "Created #{result.incidents.length} incident reports of #{user_cnt} users and #{vps_cnt} VPS:\n"

        result.incidents.each do |inc|
          text << "  Incident ##{inc.id}: user=#{inc.user_id} vps=#{inc.vps_id}\n"
        end
      else
        text << "Created #{result.incidents.length} incident reports of #{user_cnt} users and #{vps_cnt} VPS\n"
      end

      mail_custom({
                    user: nil,
                    vars: {},
                    from: result.reply[:from],
                    to: result.reply[:to],
                    in_reply_to: message.message_id,
                    references: message.message_id,
                    subject: "Re: #{message.subject}",
                    text_plain: text
                  })
    end
  end
end
