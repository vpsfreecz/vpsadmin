namespace :vpsadmin do
  namespace :requests do
    desc 'Check client IPs on registration requests'
    task :check_registration_ips do
      token = ::SysConfig.get(:plugin_requests, :ipqs_key)
      ipqs = VpsAdmin::API::Plugins::Requests::IPQS.new(token)

      ::RegistrationRequest.where(
        state: ::RegistrationRequest.states[:awaiting],
      ).where(
        'ip_checked IS NULL OR ip_checked = 0'
      ).where.not(
        client_ip_addr: nil,
      ).order('id').each do |req|
        resp = ipqs.check_ip(req.client_ip_addr)

        unless resp.success?
          req.update!(
            ip_checked: true,
            ip_request_id: resp[:request_id],
            ip_success: false,
            ip_message: resp[:message],
            ip_errors: resp[:errors] && resp[:errors].join('; '),
          )
          next
        end

        req.update!(
          ip_checked: true,
          ip_request_id: resp[:request_id],
          ip_success: true,
          ip_proxy: resp[:proxy],
          ip_crawler: resp[:crawler],
          ip_recent_abuse: resp[:recent_abuse],
          ip_vpn: resp[:vpn],
          ip_tor: resp[:tor],
          ip_fraud_score: resp[:fraud_score],
        )
      end
    end

    desc 'Check client emails on registration requests'
    task :check_registration_mails do
      token = ::SysConfig.get(:plugin_requests, :ipqs_key)
      ipqs = VpsAdmin::API::Plugins::Requests::IPQS.new(token)

      ::RegistrationRequest.where(
        state: ::RegistrationRequest.states[:awaiting],
      ).where(
        'mail_checked IS NULL OR mail_checked = 0'
      ).order('id').each do |req|
        resp = ipqs.check_mail(req.email)

        unless resp.success?
          req.update!(
            mail_checked: true,
            mail_request_id: resp[:request_id],
            mail_success: false,
            mail_message: resp[:message],
            mail_errors: resp[:errors] && resp[:errors].join('; '),
          )
          next
        end

        req.update!(
          mail_checked: true,
          mail_request_id: resp[:request_id],
          mail_success: true,
          mail_valid: resp[:valid],
          mail_disposable: resp[:disposable],
          mail_timed_out: resp[:timed_out],
          mail_deliverability: resp[:deliverability],
          mail_catch_all: resp[:catch_all],
          mail_leaked: resp[:leaked],
          mail_suspect: resp[:suspect],
          mail_smtp_score: resp[:smtp_score],
          mail_overall_score: resp[:overall_score],
          mail_fraud_score: resp[:fraud_score],
          mail_dns_valid: resp[:dns_valid],
          mail_honeypot: resp[:honeypot],
          mail_spam_trap_score: resp[:spam_trap_score],
          mail_recent_abuse: resp[:recent_abuse],
          mail_frequent_complainer: resp[:frequent_complaner],
        )
      end
    end

    desc 'Check registration requests'
    task check_registrations: %i(check_registration_ips check_registration_mails)
  end
end
