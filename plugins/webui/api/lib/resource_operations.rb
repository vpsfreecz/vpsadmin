operations = VpsAdmin::API::Events::ResourceOperations

operations.register_resource(
  'HelpBox',
  api_resources: 'VpsAdmin::API::Resources::HelpBox',
  actions: %i[created updated deleted],
  topic: :system,
  audience: :admin
)
operations.register_resource(
  'WebuiUserSetting',
  api_resources: 'VpsAdmin::API::Resources::WebuiUserSetting',
  actions: %i[created updated deleted],
  topic: :account,
  audience: :account
)
