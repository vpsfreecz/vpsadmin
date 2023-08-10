module VpsAdmin::API::Tasks
  class Mail < Base
    COUNT = ENV['COUNT'] ? ENV['COUNT'].to_i : 10

    # Mail daily report to administrators.
    #
    # Accepts the following environment variables:
    # [VPSADMIN_LANG]: Language in which to send the daily report,
    #                  defaults to 'en'
    def daily_report
      lang = ::Language.find_by!(code: ENV['VPSADMIN_LANG'] || 'en')
      TransactionChains::Mail::DailyReport.fire(lang)
    end

    # Process incoming mail
    #
    # Accepts the following environment variables:
    # [COUNT]: Number of messages to fetch from each mailbox
    def process
      ::Mailbox.all.each do |mailbox|
        retriever = ::Mail::POP3.new(
          address: mailbox.server,
          port: mailbox.port,
          user_name: mailbox.user,
          password: mailbox.password,
          enable_ssl: mailbox.enable_ssl,
        )

        #retriever.all.each do |m|
        retriever.find_and_delete(count: COUNT).each do |m|
          if handle_message(mailbox, m)
            puts "#{mailbox.label}: processed message #{m.subject}"
          else
            puts "#{mailbox.label}: ignoring message #{m.subject}"
          end
        end
      end
    end

    protected
    def handle_message(mailbox, m)
      handled = false

      mailbox.mailbox_handlers.each do |handler|
        instance = Object.const_get(handler.class_name).new(mailbox)
        ret = instance.handle_message(m)
        handled = true if ret

        if ret == :continue
          next
        elsif ret == :stop || (ret && !handler.continue)
          return handled
        end
      end

      handled
    end
  end
end
