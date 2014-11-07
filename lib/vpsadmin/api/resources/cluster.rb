class VpsAdmin::API::Resources::Cluster < HaveAPI::Resource
  version 1
  desc 'Manage cluster'
  singular true

  class PublicOverview < HaveAPI::Action

  end

  class PublicStatus < HaveAPI::Action

  end

  class FullOverview < HaveAPI::Action

  end

  include VpsAdmin::API::Maintainable::Action
end
