VpsAdmin::API::Plugin.register(:cop) do
  name 'Cop'
  description 'Monitors new users to find potential abusers'
  version '0.1.0'
  author 'Jakub Skokan'
  email 'jakub.skokan@vpsfree.cz'
  components :api

  config do
    ::MailTemplate.register :policy_violation, vars: {
            violation: '::PolicyViolation',
            object: 'instance of object that violated a policy',
        }
  end
end
