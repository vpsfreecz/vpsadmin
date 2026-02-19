# frozen_string_literal: true

RSpec.describe 'VpsAdmin::API::Resources::UserClusterResourcePackage' do
  let!(:records) do
    cpu_resource = ClusterResource.create!(
      name: 'spec_ucrp_cpu',
      label: 'Spec UCRP CPU',
      min: 1,
      max: 128,
      stepsize: 1,
      resource_type: :numeric
    )

    mem_resource = ClusterResource.create!(
      name: 'spec_ucrp_mem',
      label: 'Spec UCRP MEM',
      min: 256,
      max: 262_144,
      stepsize: 256,
      resource_type: :numeric
    )

    disk_resource = ClusterResource.create!(
      name: 'spec_ucrp_disk',
      label: 'Spec UCRP DISK',
      min: 1,
      max: 10_000,
      stepsize: 1,
      resource_type: :numeric
    )

    package_a = ClusterResourcePackage.create!(
      label: 'Spec UCRP Package A'
    )

    package_b = ClusterResourcePackage.create!(
      label: 'Spec UCRP Package B'
    )

    package_a_cpu_item = ClusterResourcePackageItem.create!(
      cluster_resource_package: package_a,
      cluster_resource: cpu_resource,
      value: 2
    )

    ClusterResourcePackageItem.create!(
      cluster_resource_package: package_a,
      cluster_resource: mem_resource,
      value: 4096
    )

    ClusterResourcePackageItem.create!(
      cluster_resource_package: package_a,
      cluster_resource: disk_resource,
      value: 50
    )

    ClusterResourcePackageItem.create!(
      cluster_resource_package: package_b,
      cluster_resource: cpu_resource,
      value: 4
    )

    seed_user_cluster_resources!(
      [user, other_user, support],
      [environment, other_environment],
      [cpu_resource, mem_resource, disk_resource]
    )

    user_pkg_a = UserClusterResourcePackage.create!(
      environment: environment,
      user: user,
      cluster_resource_package: package_a,
      added_by: admin,
      comment: 'User package A'
    )

    other_user_pkg = UserClusterResourcePackage.create!(
      environment: environment,
      user: other_user,
      cluster_resource_package: package_a,
      added_by: admin,
      comment: 'Other user package'
    )

    user_pkg_other_env = UserClusterResourcePackage.create!(
      environment: other_environment,
      user: user,
      cluster_resource_package: package_a,
      added_by: admin,
      comment: 'User package other env'
    )

    support_pkg = UserClusterResourcePackage.create!(
      environment: environment,
      user: support,
      cluster_resource_package: package_a,
      added_by: admin,
      comment: 'Support package'
    )

    nil_added_by_pkg = UserClusterResourcePackage.create!(
      environment: environment,
      user: other_user,
      cluster_resource_package: package_b,
      added_by: nil,
      comment: 'Nil added_by package'
    )

    {
      cpu_resource: cpu_resource,
      mem_resource: mem_resource,
      disk_resource: disk_resource,
      package_a: package_a,
      package_b: package_b,
      package_a_cpu_item: package_a_cpu_item,
      user_pkg_a: user_pkg_a,
      other_user_pkg: other_user_pkg,
      user_pkg_other_env: user_pkg_other_env,
      support_pkg: support_pkg,
      nil_added_by_pkg: nil_added_by_pkg
    }
  end

  before do
    header 'Accept', 'application/json'
  end

  def environment
    SpecSeed.environment
  end

  def other_environment
    SpecSeed.other_environment
  end

  def admin
    SpecSeed.admin
  end

  def support
    SpecSeed.support
  end

  def user
    SpecSeed.user
  end

  def other_user
    SpecSeed.other_user
  end

  def cpu_resource
    records.fetch(:cpu_resource)
  end

  def mem_resource
    records.fetch(:mem_resource)
  end

  def disk_resource
    records.fetch(:disk_resource)
  end

  def package_a
    records.fetch(:package_a)
  end

  def package_b
    records.fetch(:package_b)
  end

  def package_a_cpu_item
    records.fetch(:package_a_cpu_item)
  end

  def user_pkg_a
    records.fetch(:user_pkg_a)
  end

  def other_user_pkg
    records.fetch(:other_user_pkg)
  end

  def user_pkg_other_env
    records.fetch(:user_pkg_other_env)
  end

  def support_pkg
    records.fetch(:support_pkg)
  end

  def nil_added_by_pkg
    records.fetch(:nil_added_by_pkg)
  end

  def seed_user_cluster_resources!(users, environments, resources)
    users.each do |usr|
      environments.each do |env|
        resources.each do |resource|
          UserClusterResource.create!(
            user: usr,
            environment: env,
            cluster_resource: resource,
            value: 0
          )
        end
      end
    end
  end

  def index_path
    vpath('/user_cluster_resource_packages')
  end

  def show_path(id)
    vpath("/user_cluster_resource_packages/#{id}")
  end

  def items_path(user_pkg_id)
    vpath("/user_cluster_resource_packages/#{user_pkg_id}/items")
  end

  def item_path(user_pkg_id, item_id)
    vpath("/user_cluster_resource_packages/#{user_pkg_id}/items/#{item_id}")
  end

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def json_post(path, payload)
    post path, JSON.dump(payload), {
      'CONTENT_TYPE' => 'application/json'
    }
  end

  def json_put(path, payload)
    put path, JSON.dump(payload), {
      'CONTENT_TYPE' => 'application/json'
    }
  end

  def json_delete(path)
    delete path, {}, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def user_cluster_resource_packages
    json.dig('response', 'user_cluster_resource_packages')
  end

  def user_cluster_resource_package
    json.dig('response', 'user_cluster_resource_package')
  end

  def items
    json.dig('response', 'items') || json.dig('response', 'cluster_resource_package_items')
  end

  def item
    json.dig('response', 'item') || json.dig('response', 'cluster_resource_package_item')
  end

  def resource_id(value)
    return value['id'] if value.is_a?(Hash)

    value
  end

  def row_environment_id(row)
    resource_id(row['environment'])
  end

  def row_user_id(row)
    resource_id(row['user'])
  end

  def row_package_id(row)
    resource_id(row['cluster_resource_package'])
  end

  def item_resource_id(row)
    resource_id(row['cluster_resource'])
  end

  def item_value(row)
    row['value']
  end

  def find_item(rows, resource)
    rows.find { |row| item_resource_id(row).to_i == resource.id }
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected status #{code} for #{path}, got #{last_response.status} body=#{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  describe 'Index' do
    it 'rejects unauthenticated access' do
      json_get index_path

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows normal users to list only their assignments' do
      as(user) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)
      ids = user_cluster_resource_packages.map { |row| row['id'] }
      expect(ids).to include(user_pkg_a.id, user_pkg_other_env.id)
      expect(ids).not_to include(other_user_pkg.id)
    end

    it 'allows support users to list only their assignments' do
      as(support) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)
      ids = user_cluster_resource_packages.map { |row| row['id'] }
      expect(ids).to include(support_pkg.id)
      expect(ids).not_to include(user_pkg_a.id)
    end

    it 'allows admin to list all assignments' do
      as(admin) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)
      ids = user_cluster_resource_packages.map { |row| row['id'] }
      expect(ids).to include(user_pkg_a.id, other_user_pkg.id, user_pkg_other_env.id, support_pkg.id)
    end

    it 'filters by environment' do
      as(admin) do
        json_get index_path, user_cluster_resource_package: {
          environment: environment.id
        }
      end

      expect_status(200)
      ids = user_cluster_resource_packages.map { |row| row['id'] }
      expect(ids).to include(user_pkg_a.id, other_user_pkg.id, support_pkg.id)
      expect(ids).not_to include(user_pkg_other_env.id)
    end

    it 'filters by user for admins' do
      as(admin) do
        json_get index_path, user_cluster_resource_package: {
          user: user.id
        }
      end

      expect_status(200)
      ids = user_cluster_resource_packages.map { |row| row['id'] }
      expect(ids).to contain_exactly(user_pkg_a.id, user_pkg_other_env.id)
    end

    it 'filters by added_by when nil' do
      as(admin) do
        json_get index_path, user_cluster_resource_package: {
          added_by: nil
        }
      end

      expect_status(200)
      ids = user_cluster_resource_packages.map { |row| row['id'] }
      expect(ids).to contain_exactly(nil_added_by_pkg.id)
    end

    it 'returns total_count meta when requested' do
      as(admin) { json_get index_path, _meta: { count: true } }

      expect_status(200)
      expect(json.dig('response', '_meta', 'total_count')).to eq(UserClusterResourcePackage.count)
    end

    it 'supports limit pagination' do
      as(admin) { json_get index_path, user_cluster_resource_package: { limit: 1 } }

      expect_status(200)
      expect(user_cluster_resource_packages.length).to eq(1)
    end

    it 'supports from_id pagination' do
      boundary = user_pkg_a.id
      as(admin) { json_get index_path, user_cluster_resource_package: { from_id: boundary } }

      expect_status(200)
      ids = user_cluster_resource_packages.map { |row| row['id'].to_i }
      expect(ids.all? { |id| id > boundary }).to be(true)
    end
  end

  describe 'Show' do
    it 'rejects unauthenticated access' do
      json_get show_path(user_pkg_a.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows normal users to show their assignment' do
      as(user) { json_get show_path(user_pkg_a.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(user_cluster_resource_package['id']).to eq(user_pkg_a.id)
      expect(row_environment_id(user_cluster_resource_package)).to eq(environment.id)
      expect(user_cluster_resource_package['label']).to eq(package_a.label)
    end

    it 'hides other users assignments from normal users' do
      as(user) { json_get show_path(other_user_pkg.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows admin to show any assignment' do
      as(admin) { json_get show_path(other_user_pkg.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(row_user_id(user_cluster_resource_package)).to eq(other_user.id)
      expect(row_package_id(user_cluster_resource_package)).to eq(package_a.id)
    end

    it 'returns 404 for unknown assignments' do
      missing = UserClusterResourcePackage.maximum(:id).to_i + 100
      as(admin) { json_get show_path(missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Create' do
    it 'rejects unauthenticated access' do
      json_post index_path, user_cluster_resource_package: {
        environment: environment.id,
        user: user.id,
        cluster_resource_package: package_b.id,
        comment: 'Spec create'
      }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(user) do
        json_post index_path, user_cluster_resource_package: {
          environment: environment.id,
          user: user.id,
          cluster_resource_package: package_b.id,
          comment: 'Spec create'
        }
      end

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(support) do
        json_post index_path, user_cluster_resource_package: {
          environment: environment.id,
          user: support.id,
          cluster_resource_package: package_b.id,
          comment: 'Spec create'
        }
      end

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to create a new assignment' do
      as(admin) do
        json_post index_path, user_cluster_resource_package: {
          environment: other_environment.id,
          user: other_user.id,
          cluster_resource_package: package_b.id,
          comment: 'Spec create admin'
        }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(row_user_id(user_cluster_resource_package)).to eq(other_user.id)
      expect(row_environment_id(user_cluster_resource_package)).to eq(other_environment.id)
      expect(row_package_id(user_cluster_resource_package)).to eq(package_b.id)

      record = UserClusterResourcePackage.find_by(
        environment: other_environment,
        user: other_user,
        cluster_resource_package: package_b
      )
      expect(record).not_to be_nil
    end

    it 'returns validation errors for missing required fields' do
      as(admin) do
        json_post index_path, user_cluster_resource_package: {
          environment: environment.id,
          user: user.id,
          comment: 'Missing package'
        }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      errors = json.dig('response', 'errors') || json['errors']
      expect(errors).to be_a(Hash)
      expect(errors.keys.map(&:to_s)).to include('cluster_resource_package')
    end
  end

  describe 'Update' do
    it 'rejects unauthenticated access' do
      json_put show_path(user_pkg_a.id), user_cluster_resource_package: {
        comment: 'Updated'
      }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(user) do
        json_put show_path(user_pkg_a.id), user_cluster_resource_package: {
          comment: 'Updated'
        }
      end

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(support) do
        json_put show_path(user_pkg_a.id), user_cluster_resource_package: {
          comment: 'Updated'
        }
      end

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to update an assignment' do
      as(admin) do
        json_put show_path(user_pkg_a.id), user_cluster_resource_package: {
          comment: 'Updated by admin'
        }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(user_cluster_resource_package['comment']).to eq('Updated by admin')
      expect(UserClusterResourcePackage.find(user_pkg_a.id).comment).to eq('Updated by admin')
    end

    it 'returns validation errors for missing input' do
      as(admin) do
        json_put show_path(user_pkg_a.id), user_cluster_resource_package: {}
      end

      expect_status(200)
      expect(json['status']).to be(false)
      errors = json.dig('response', 'errors') || json['errors']
      expect(errors).to be_a(Hash)
      expect(errors.keys.map(&:to_s)).to include('comment')
    end
  end

  describe 'Delete' do
    it 'rejects unauthenticated access' do
      json_delete show_path(user_pkg_a.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(user) { json_delete show_path(user_pkg_a.id) }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(support) { json_delete show_path(user_pkg_a.id) }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to delete an assignment' do
      as(admin) { json_delete show_path(user_pkg_a.id) }

      expect_status(200)
      expect(UserClusterResourcePackage.find_by(id: user_pkg_a.id)).to be_nil
    end
  end

  describe 'Item Index' do
    it 'rejects unauthenticated access' do
      json_get items_path(user_pkg_a.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows normal users to list their package items' do
      as(user) { json_get items_path(user_pkg_a.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(find_item(items, cpu_resource)).not_to be_nil
      expect(find_item(items, mem_resource)).not_to be_nil
      expect(find_item(items, disk_resource)).not_to be_nil
    end

    it 'hides other users package items from normal users' do
      as(user) { json_get items_path(other_user_pkg.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows admin to list any package items' do
      as(admin) { json_get items_path(other_user_pkg.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(find_item(items, cpu_resource)).not_to be_nil
    end
  end

  describe 'Item Show' do
    it 'rejects unauthenticated access' do
      json_get item_path(user_pkg_a.id, package_a_cpu_item.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows normal users to show their package item' do
      as(user) { json_get item_path(user_pkg_a.id, package_a_cpu_item.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(item_resource_id(item)).to eq(cpu_resource.id)
      expect(item_value(item)).to eq(package_a_cpu_item.value)
    end

    it 'hides other users package items from normal users' do
      as(user) { json_get item_path(other_user_pkg.id, package_a_cpu_item.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows admin to show any package item' do
      as(admin) { json_get item_path(other_user_pkg.id, package_a_cpu_item.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(item_resource_id(item)).to eq(cpu_resource.id)
    end
  end
end
