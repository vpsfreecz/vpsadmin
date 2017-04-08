namespace :vpsadmin do
  namespace :cop do
    task :check do
      VpsAdmin::API::Plugins::Cop.policies.each do |policy|
        policy.check
      end
    end
  end
end
