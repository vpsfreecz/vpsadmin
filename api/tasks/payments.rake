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
  end
end
