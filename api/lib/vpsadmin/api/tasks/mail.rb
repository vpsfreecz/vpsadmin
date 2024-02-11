module VpsAdmin::API::Tasks
  class Mail < Base
    FOLDERS = %w[INBOX Junk]

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
    # [EXECUTE]: Received emails are deleted and persistent changes are made only
    #            when set to `yes`
    def process
      dry_run = ENV['EXECUTE'] != 'yes'

      ::Mailbox.all.each do |mailbox|
        FOLDERS.each do |folder|
          check_mailbox(mailbox, folder, dry_run: dry_run)
        end
      end
    end

    protected

    def check_mailbox(mailbox, folder, dry_run:)
      retriever = ::Mail::IMAP.new(
        address: mailbox.server,
        port: mailbox.port,
        user_name: mailbox.user,
        password: mailbox.password,
        enable_ssl: mailbox.enable_ssl
      )

      messages =
        if dry_run
          warn 'Dry run: received messages are not removed from the mail server'
          retriever.all(mailbox: folder)
        else
          retriever.find_and_delete(mailbox: folder, count: COUNT)
        end

      messages.each do |m|
        if handle_message(mailbox, m, dry_run: dry_run)
          puts "#{mailbox.label}/#{folder}: processed message #{m.subject}"
        else
          puts "#{mailbox.label}/#{folder}: ignoring message #{m.subject}"
        end
      end
    end

    def handle_message(mailbox, m, dry_run:)
      handled = false

      mailbox.mailbox_handlers.each do |handler|
        instance = Object.const_get(handler.class_name).new(mailbox)
        ret = instance.handle_message(m, dry_run: dry_run)
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
