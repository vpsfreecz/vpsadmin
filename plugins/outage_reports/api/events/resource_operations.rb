operations = VpsAdmin::API::Events::ResourceOperations

operations.register_resource(
  'Outage',
  api_resources: 'VpsAdmin::API::Resources::Outage',
  actions: %i[created updated],
  topic: :outages,
  audience: :admin
)
operations.register_resource(
  'OutageEntity',
  api_resources: 'VpsAdmin::API::Resources::Outage::Entity',
  actions: %i[created deleted],
  topic: :outages,
  audience: :admin
)
operations.register_resource(
  'OutageHandler',
  api_resources: 'VpsAdmin::API::Resources::Outage::Handler',
  actions: %i[created updated deleted],
  topic: :outages,
  audience: :admin
)
operations.register_resource(
  'OutageSecurityAdvisory',
  api_resources: 'VpsAdmin::API::Resources::OutageSecurityAdvisory',
  actions: %i[created deleted],
  topic: :outages,
  audience: :admin
)
operations.register_resource(
  'OutageUpdate',
  api_resources: 'VpsAdmin::API::Resources::OutageUpdate',
  actions: %i[created],
  topic: :outages,
  audience: :admin
)
