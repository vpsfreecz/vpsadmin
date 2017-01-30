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

    desc 'Process fetched transactions'
    task :process do
      ::UserAccount.accept_payments
    end

    desc 'Fetch and process transactions'
    task accept: %i(fetch process)
  end
end
