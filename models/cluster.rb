class Cluster
  include VpsAdmin::API::Maintainable::Model

  maintenance_children :environments

  def environments
    ::Environment
  end
end
