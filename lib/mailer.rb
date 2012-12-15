require 'net/smtp'
require 'lib/executor'

class Mailer < Executor
	def send
		from = "vpsAdmin - vpsFree.cz <podpora@vpsfree.cz>"
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

		msg = <<MSG
#{headers}
#{@params["msg"]}
MSG
		begin
			Net::SMTP.start($APP_CONFIG[:mailer][:smtp_server], $APP_CONFIG[:mailer][:smtp_port]) do |smtp|
				smtp.send_message(msg, "podpora@vpsfree.cz", [@params["to"],] + @params["cc"] + @params["bcc"])
			end
		rescue
			@output[:exception] = $!.inspect
			@output[:msg] = $!.message
			return {:ret => :failed}
		end
		
		{:ret => :ok}
	end
end
