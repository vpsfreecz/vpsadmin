VpsAdmin::API::Events::ResourceOperations.register_resource(
  'UserRequest',
  api_resources: %w[
    VpsAdmin::API::Resources::UserRequest::Change
    VpsAdmin::API::Resources::UserRequest::Registration
  ],
  actions: %i[created updated],
  topic: :requests,
  audience: :account,
  logical_name: 'request'
)
