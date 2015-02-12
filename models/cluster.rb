class Cluster
  include VpsAdmin::API::Maintainable::Model

  maintenance_children :environments, :locations

  def environments
    ::Environment
  end

  def locations
    ::Location
  end
end
