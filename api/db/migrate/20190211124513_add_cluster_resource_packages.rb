class AddClusterResourcePackages < ActiveRecord::Migration
  class User < ::ActiveRecord::Base ; end
  class UserClusterResource < ::ActiveRecord::Base ; end
  class ClusterResourcePackage < ::ActiveRecord::Base ; end
  class UserClusterResourcePackage < ::ActiveRecord::Base ; end
  class User < ::ActiveRecord::Base ; end
  class Environment < ::ActiveRecord::Base ; end

  def change
    create_table :cluster_resource_packages do |t|
      t.string      :label,                     null: false
      t.references  :environment,               null: true
      t.references  :user,                      null: true
      t.timestamps                              null: false
    end

    add_index :cluster_resource_packages, :environment_id
    add_index :cluster_resource_packages, :user_id
    add_index :cluster_resource_packages,
              %i(environment_id user_id),
              unique: true,
              name: :cluster_resource_packages_unique

    create_table :cluster_resource_package_items do |t|
      t.references  :cluster_resource_package,  null: false
      t.references  :cluster_resource,          null: false
      t.decimal     :value,                     null: false, precision: 40, scale: 0
    end

    add_index :cluster_resource_package_items,
              %i(cluster_resource_package_id cluster_resource_id),
              unique: true,
              name: :cluster_resource_package_items_unique
    add_index :cluster_resource_package_items,
              :cluster_resource_package_id,
              name: :cluster_resource_package_id
    add_index :cluster_resource_package_items,
              :cluster_resource_id,
              name: :cluster_resource_id

    create_table :user_cluster_resource_packages do |t|
      t.references  :environment
      t.references  :user,                      null: false
      t.references  :cluster_resource_package,  null: false
      t.integer     :added_by_id,               null: true
      t.string      :comment,                   null: false, default: ''
      t.timestamps                              null: false
    end

    add_index :user_cluster_resource_packages,
              :environment_id,
              name: :environment_id
    add_index :user_cluster_resource_packages,
              :user_id,
              name: :user_id
    add_index :user_cluster_resource_packages,
              :cluster_resource_package_id,
              name: :cluster_resource_package_id
    add_index :user_cluster_resource_packages,
              :added_by_id,
              name: :added_by_id

    create_table :default_user_cluster_resource_packages do |t|
      t.references  :environment,               null: false
      t.references  :cluster_resource_package,  null: false
    end

    add_index :default_user_cluster_resource_packages,
              %i(environment_id cluster_resource_package_id),
              unique: true,
              name: :default_user_cluster_resource_packages_unique

    reversible do |dir|
      dir.up do
        ActiveRecord::Base.transaction do
          ::User.where('object_state < 3').each do |user|
            ::Environment.all.each do |env|
              create_user_package(user, env)
            end
          end
        end
      end
    end
  end

  protected
  def create_user_package(user, env)
    pkg = ::ClusterResourcePackage.create!(
      label: 'Personal package',
      environment_id: env.id,
      user_id: user.id,
    )

    ::UserClusterResource.where(
      environment_id: env.id,
      user_id: user.id,
    ).each do |ucr|
      ::ClusterResourcePackageItem.create!(
        cluster_resource_package_id: pkg.id,
        cluster_resource_id: ucr.cluster_resource_id,
        value: ucr.value,
      )
    end

    ::UserClusterResourcePackage.create!(
      environment_id: env.id,
      user_id: user.id,
      cluster_resource_package_id: pkg.id,
    )
  end
end
