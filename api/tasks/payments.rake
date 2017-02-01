namespace :vpsadmin do
  namespace :payments do
    desc 'Fetch transactions from the bank'
    task :fetch do
      if ENV['BACKEND'].nil?
        warn "Specify which BACKEND to use"
        exit(false)
      end

      b = VpsAdmin::API::Plugins::Payments.get_backend(ENV['BACKEND'].strip.to_sym)

      unless b
        warn "BACKEND '#{ENV['BACKEND']}' not found"
        exit(false)
      end

      b.new.fetch
    end

    desc 'Accept fetched transactions'
    task :accept do
      ::UserAccount.accept_payments
    end

    desc 'Fetch and accept transactions'
    task process: %i(fetch accept)

    desc 'Send an e-mail about received payments'
    task :mail_overview do
      VpsAdmin::API::Plugins::Payments::TransactionChains::MailOverview.fire(
          ENV['PERIOD'] ? ENV['PERIOD'].to_i : 60*60*24,
          ENV['VPSADMIN_LANG'] \
            ? ::Language.find_by!(code: ENV['VPSADMIN_LANG']) \
            : ::Language.take!
      )
    end
  end
end
