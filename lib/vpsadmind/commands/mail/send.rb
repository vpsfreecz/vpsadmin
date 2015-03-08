module VpsAdmind
  class Commands::Mail::Send < Commands::Base
    handle 9001

    def exec
      m = Mail.new
      m.to = @to
      m.from = @from
      m.cc = @cc
      m.bcc = @bcc
      m.reply_to = @reply_to
      m.return_path = @return_path

      m.message_id = @message_id if @message_id
      m.in_reply_to = @in_reply_to if @in_reply_to
      m.references = @references if @references

      m.subject = @subject

      if @text_plain
        p = Mail::Part.new
        p.content_type 'text/plain; charset=UTF-8'
        p.body = @text_plain
        m.text_part = p
      end

      if @text_html
        p = Mail::Part.new
        p.content_type 'text/html; charset=UTF-8'
        p.body = @text_html
        m.html_part = p
      end

      m.header['X-Mailer'] = 'vpsAdmin'

      m.delivery_method :smtp, :address => $CFG.get(:mailer, :smtp_server), :port => $CFG.get(:mailer, :smtp_port)

      tries = 0

      begin
        m.deliver

      rescue Timeout::Error => e
        tries += 1

        if tries <= 3
          log(:work, self,  'Timeout when sending email: retrying')
          retry
        end

        log(:work, self,  'Timeout when sending email: out of attempts')
        raise e
      end

      ok
    end

    def rollback
      ok
    end
  end
end
