operations = VpsAdmin::API::Events::ResourceOperations

operations.register_resource(
  'IncomingPayment',
  api_resources: 'VpsAdmin::API::Resources::IncomingPayment',
  actions: %i[updated],
  topic: :payments,
  audience: :admin
)
operations.register_resource(
  'UserAccount',
  api_resources: 'VpsAdmin::API::Resources::UserAccount',
  actions: %i[updated],
  topic: :payments,
  audience: :account
)
operations.register_resource(
  'UserPayment',
  api_resources: 'VpsAdmin::API::Resources::UserPayment',
  actions: %i[created],
  topic: :payments,
  audience: :account
)
