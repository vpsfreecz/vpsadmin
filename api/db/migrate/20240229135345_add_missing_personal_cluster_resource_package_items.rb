class AddMissingPersonalClusterResourcePackageItems < ActiveRecord::Migration[7.1]
  class ClusterResource < ActiveRecord::Base; end

  class ClusterResourcePackage < ActiveRecord::Base
    has_many :cluster_resource_package_items
  end

  class ClusterResourcePackageItem < ActiveRecord::Base
    belongs_to :cluster_resource_package
  end

  def up
    cluster_resources = ClusterResource.all

    ClusterResourcePackage.where.not(user_id: nil).each do |crp|
      cluster_resources.each do |cr|
        item = crp.cluster_resource_package_items.create!(
          cluster_resource_id: cr.id,
          value: 0
        )

        puts "Created item id=#{item.id} for user=#{crp.user_id} pkg=#{crp.id} resource=#{cr.name}"
      rescue ActiveRecord::RecordNotUnique
        # continue
      end
    end
  end

  def down
    # nothing to do
  end
end
