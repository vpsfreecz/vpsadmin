# frozen_string_literal: true

RSpec.describe 'VpsAdmin::API::Resources::ClusterResourcePackage' do
  let!(:cpu_resource) do
    ClusterResource.create!(
      name: 'spec_pkg_cpu',
      label: 'Spec Pkg CPU',
      min: 1,
      max: 64,
      stepsize: 1,
      resource_type: :numeric
    )
  end

  let!(:mem_resource) do
    ClusterResource.create!(
      name: 'spec_pkg_mem',
      label: 'Spec Pkg MEM',
      min: 256,
      max: 262_144,
      stepsize: 256,
      resource_type: :numeric
    )
  end

  let!(:disk_resource) do
    ClusterResource.create!(
      name: 'spec_pkg_disk',
      label: 'Spec Pkg DISK',
      min: 1,
      max: 1_000,
      stepsize: 1,
      resource_type: :numeric
    )
  end

  let!(:package_a) do
    ClusterResourcePackage.create!(
      label: 'Spec Package A'
    )
  end

  let!(:package_b) do
    ClusterResourcePackage.create!(
      label: 'Spec Package B'
    )
  end

  before do
    header 'Accept', 'application/json'

    ClusterResourcePackageItem.create!(
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
      value: 20
    )
  end

  def index_path
    vpath('/cluster_resource_packages')
  end

  def show_path(id)
    vpath("/cluster_resource_packages/#{id}")
  end

  def items_path(package_id)
    vpath("/cluster_resource_packages/#{package_id}/items")
  end

  def item_path(package_id, item_id)
    vpath("/cluster_resource_packages/#{package_id}/items/#{item_id}")
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

  def packages
    json.dig('response', 'cluster_resource_packages')
  end

  def package
    json.dig('response', 'cluster_resource_package')
  end

  def items
    json.dig('response', 'items') || json.dig('response', 'cluster_resource_package_items')
  end

  def item
    json.dig('response', 'item') || json.dig('response', 'cluster_resource_package_item')
  end

  def package_a_cpu_item
    ClusterResourcePackageItem.find_by!(
      cluster_resource_package: package_a,
      cluster_resource: cpu_resource
    )
  end

  def item_resource_id(row)
    value = row['cluster_resource']
    return value['id'] if value.is_a?(Hash)

    value
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

    it 'forbids normal users' do
      as(SpecSeed.user) { json_get index_path }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(SpecSeed.support) { json_get index_path }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to list packages' do
      as(SpecSeed.admin) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)
      labels = packages.map { |row| row['label'] }
      expect(labels).to include('Spec Package A', 'Spec Package B')
    end

    it 'filters by user when nil' do
      package_user = ClusterResourcePackage.create!(
        label: 'Spec Package User',
        environment: SpecSeed.environment,
        user: SpecSeed.user
      )

      as(SpecSeed.admin) do
        json_get index_path, cluster_resource_package: { user: nil }
      end

      expect_status(200)
      ids = packages.map { |row| row['id'] }
      expect(ids).to include(package_a.id, package_b.id)
      expect(ids).not_to include(package_user.id)
    end

    it 'returns total_count meta when requested' do
      as(SpecSeed.admin) { json_get index_path, _meta: { count: true } }

      expect_status(200)
      expect(json.dig('response', '_meta', 'total_count')).to eq(ClusterResourcePackage.count)
    end

    it 'supports limit pagination' do
      as(SpecSeed.admin) { json_get index_path, cluster_resource_package: { limit: 1 } }

      expect_status(200)
      expect(packages.length).to eq(1)
    end

    it 'supports from_id pagination' do
      boundary = ClusterResourcePackage.find_by!(label: 'Spec Package A').id
      as(SpecSeed.admin) { json_get index_path, cluster_resource_package: { from_id: boundary } }

      expect_status(200)
      ids = packages.map { |row| row['id'] }
      expect(ids).to all(be > boundary)
    end
  end

  describe 'Show' do
    it 'rejects unauthenticated access' do
      json_get show_path(package_a.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) { json_get show_path(package_a.id) }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(SpecSeed.support) { json_get show_path(package_a.id) }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'shows a package for admin users' do
      as(SpecSeed.admin) { json_get show_path(package_a.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(package['id']).to eq(package_a.id)
      expect(package['label']).to eq('Spec Package A')
    end

    it 'returns 404 for unknown package' do
      missing = ClusterResourcePackage.maximum(:id).to_i + 100
      as(SpecSeed.admin) { json_get show_path(missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Create' do
    it 'rejects unauthenticated access' do
      json_post index_path, cluster_resource_package: { label: 'Spec Package Created' }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) do
        json_post index_path, cluster_resource_package: { label: 'Spec Package Created' }
      end

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(SpecSeed.support) do
        json_post index_path, cluster_resource_package: { label: 'Spec Package Created' }
      end

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to create a package' do
      as(SpecSeed.admin) do
        json_post index_path, cluster_resource_package: { label: 'Spec Package Created' }
      end

      expect_status(200)
      expect(json['status']).to be(true)

      record = ClusterResourcePackage.find_by!(label: 'Spec Package Created')
      expect(record.label).to eq('Spec Package Created')
      expect(package['id']).to eq(record.id)
    end

    it 'returns validation errors for invalid label' do
      as(SpecSeed.admin) do
        json_post index_path, cluster_resource_package: { label: '' }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      errors = json.dig('response', 'errors') || json['errors']
      expect(errors).to be_a(Hash)
      expect(errors.keys.map(&:to_s)).to include('label')
    end
  end

  describe 'Update' do
    it 'rejects unauthenticated access' do
      json_put show_path(package_a.id), cluster_resource_package: { label: 'Updated Package A' }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) do
        json_put show_path(package_a.id), cluster_resource_package: { label: 'Updated Package A' }
      end

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(SpecSeed.support) do
        json_put show_path(package_a.id), cluster_resource_package: { label: 'Updated Package A' }
      end

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to update and returns the object' do
      as(SpecSeed.admin) do
        json_put show_path(package_a.id), cluster_resource_package: { label: 'Updated Package A' }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(package).to be_a(Hash)
      expect(package['label']).to eq('Updated Package A')

      record = ClusterResourcePackage.find(package_a.id)
      expect(record.label).to eq('Updated Package A')
    end

    it 'returns validation errors for invalid label' do
      as(SpecSeed.admin) do
        json_put show_path(package_a.id), cluster_resource_package: { label: '' }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      errors = json.dig('response', 'errors') || json['errors']
      expect(errors).to be_a(Hash)
      expect(errors.keys.map(&:to_s)).to include('label')
    end
  end

  describe 'Delete' do
    it 'rejects unauthenticated access' do
      json_delete show_path(package_a.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) { json_delete show_path(package_a.id) }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(SpecSeed.support) { json_delete show_path(package_a.id) }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to delete a package and its items' do
      as(SpecSeed.admin) { json_delete show_path(package_a.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(ClusterResourcePackage.where(id: package_a.id)).to be_empty
      expect(ClusterResourcePackageItem.where(cluster_resource_package_id: package_a.id)).to be_empty
    end
  end

  describe 'Item Index' do
    it 'rejects unauthenticated access' do
      json_get items_path(package_a.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) { json_get items_path(package_a.id) }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(SpecSeed.support) { json_get items_path(package_a.id) }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'lists items for admin users' do
      as(SpecSeed.admin) { json_get items_path(package_a.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(items.length).to eq(3)

      cpu_row = find_item(items, cpu_resource)
      mem_row = find_item(items, mem_resource)
      disk_row = find_item(items, disk_resource)

      expect(cpu_row).not_to be_nil
      expect(mem_row).not_to be_nil
      expect(disk_row).not_to be_nil
      expect(item_value(cpu_row).to_s).to eq('2')
      expect(item_value(mem_row).to_s).to eq('4096')
      expect(item_value(disk_row).to_s).to eq('20')
    end
  end

  describe 'Item Show' do
    it 'rejects unauthenticated access' do
      json_get item_path(package_a.id, package_a_cpu_item.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) { json_get item_path(package_a.id, package_a_cpu_item.id) }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(SpecSeed.support) { json_get item_path(package_a.id, package_a_cpu_item.id) }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'shows an item for admin users' do
      as(SpecSeed.admin) { json_get item_path(package_a.id, package_a_cpu_item.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(item).to be_a(Hash)
      expect(item_resource_id(item).to_i).to eq(cpu_resource.id)
      expect(item_value(item).to_s).to eq('2')
    end

    it 'returns 404 for unknown item' do
      missing = ClusterResourcePackageItem.maximum(:id).to_i + 100
      as(SpecSeed.admin) { json_get item_path(package_a.id, missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Item Create' do
    it 'rejects unauthenticated access' do
      json_post items_path(package_b.id), item: { cluster_resource: cpu_resource.id, value: 4 }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) do
        json_post items_path(package_b.id), item: { cluster_resource: cpu_resource.id, value: 4 }
      end

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(SpecSeed.support) do
        json_post items_path(package_b.id), item: { cluster_resource: cpu_resource.id, value: 4 }
      end

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to create an item' do
      as(SpecSeed.admin) do
        json_post items_path(package_b.id), item: { cluster_resource: cpu_resource.id, value: 4 }
      end

      expect_status(200)
      expect(json['status']).to be(true)

      created = ClusterResourcePackageItem.find_by!(
        cluster_resource_package: package_b,
        cluster_resource: cpu_resource
      )
      expect(created.value.to_s).to eq('4')
      expect(item_resource_id(item).to_i).to eq(cpu_resource.id) if item
    end

    it 'returns validation errors for missing value' do
      as(SpecSeed.admin) do
        json_post items_path(package_b.id), item: { cluster_resource: cpu_resource.id, value: nil }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      errors = json.dig('response', 'errors') || json['errors']
      expect(errors).to be_a(Hash)
      expect(errors.keys.map(&:to_s)).to include('value')
    end
  end

  describe 'Item Update' do
    it 'rejects unauthenticated access' do
      json_put item_path(package_a.id, package_a_cpu_item.id), item: { value: 4 }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) { json_put item_path(package_a.id, package_a_cpu_item.id), item: { value: 4 } }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(SpecSeed.support) { json_put item_path(package_a.id, package_a_cpu_item.id), item: { value: 4 } }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to update an item value' do
      as(SpecSeed.admin) { json_put item_path(package_a.id, package_a_cpu_item.id), item: { value: 4 } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(item).to be_a(Hash)
      expect(item_value(item).to_s).to eq('4')

      record = ClusterResourcePackageItem.find(package_a_cpu_item.id)
      expect(record.value.to_s).to eq('4')
    end

    it 'returns validation errors for missing value' do
      as(SpecSeed.admin) { json_put item_path(package_a.id, package_a_cpu_item.id), item: { value: nil } }

      expect_status(200)
      expect(json['status']).to be(false)
      errors = json.dig('response', 'errors') || json['errors']
      expect(errors).to be_a(Hash)
      expect(errors.keys.map(&:to_s)).to include('value')
    end
  end

  describe 'Item Delete' do
    it 'rejects unauthenticated access' do
      json_delete item_path(package_a.id, package_a_cpu_item.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) { json_delete item_path(package_a.id, package_a_cpu_item.id) }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(SpecSeed.support) { json_delete item_path(package_a.id, package_a_cpu_item.id) }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to delete an item' do
      item_id = package_a_cpu_item.id
      as(SpecSeed.admin) { json_delete item_path(package_a.id, item_id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(ClusterResourcePackageItem.where(id: item_id)).to be_empty
    end
  end
end
