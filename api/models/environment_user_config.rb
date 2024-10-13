require 'vpsadmin/api/cluster_resources'

class EnvironmentUserConfig < ApplicationRecord
  belongs_to :environment
  belongs_to :user

  has_paper_trail

  include VpsAdmin::API::ClusterResources
  cluster_resources optional: %i[ipv4 ipv4_private ipv6],
                    environment: -> { environment }
end
