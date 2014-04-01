require 'net/smtp'
require 'lib/executor'

class Mailer < Executor
  def send
    from = "#{@params["from_name"]} <#{@params["from_mail"]}>"
    headers = <<HEADERS
From: #{from}
To: #{@params["to"]}
Reply-To: #{from}
Return-Path: #{from}
X-Mailer: vpsAdmin
MIME-Version: 1.0
Content-type: text/#{@params["html"] ? "html" : "plain"}; charset=UTF-8
Subject: #{@params["subject"]}
HEADERS

    headers += "CC: #{@params["cc"].join(",")}\n" if @params["cc"].count > 0
    headers += "Message-ID: <#{@params["msg_id"]}>\n" unless @params["msg_id"].nil?
    headers += "In-Reply-To: <#{@params["in_reply_to"]}>\n" unless @params["in_reply_to"].nil? || @params["in_reply_to"].empty?
    headers += "References: <#{@params["references"].join("\n  ")}>\n" unless @params["references"].nil? || @params["references"].empty?

    msg = <<MSG
#{headers}
    #{@params["msg"]}
MSG
    begin
      Net::SMTP.start($CFG.get(:mailer, :smtp_server), $CFG.get(:mailer, :smtp_port)) do |smtp|
        smtp.send_message(msg, @params["from_mail"], [@params["to"],] + @params["cc"] + @params["bcc"])
      end
    rescue Timeout::Error
      retry
    rescue
      @output[:exception] = $!.inspect
      @output[:msg] = $!.message
      return {:ret => :failed}
    end

    {:ret => :ok}
  end
end
