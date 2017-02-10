module VpsAdmin::API::Plugins::Requests::TransactionChains
  module Utils
    def message_id(r, mail_id = nil)
      ::SysConfig.get(:plugin_requests, :message_id) % {
          id: r.id,
          mail_id: mail_id || r.last_mail_id,
      }
    end
  end
end
