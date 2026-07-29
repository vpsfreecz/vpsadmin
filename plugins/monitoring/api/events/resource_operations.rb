VpsAdmin::API::Events::ResourceOperations.register_resource(
  'MonitoredEvent',
  api_resources: 'VpsAdmin::API::Resources::MonitoredEvent',
  actions: %i[updated],
  topic: :monitoring,
  audience: :account
)
