namespace :vpsadmin do
  namespace :cop do
    task :check do
      violations = []

      VpsAdmin::API::Plugins::Cop.policies.each do |policy|
        ret = policy.check
        next unless ret

        violations.concat(ret)
      end

      next if violations.empty?

      VpsAdmin::API::Plugins::Cop::TransactionChains::ReportViolation.fire(violations)
    end
  end
end
