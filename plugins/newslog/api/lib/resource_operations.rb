VpsAdmin::API::Events::ResourceOperations.register_resource(
  'NewsLog',
  api_resources: 'VpsAdmin::API::Resources::NewsLog',
  actions: %i[created updated deleted],
  topic: :notifications,
  audience: :admin
)
