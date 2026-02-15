# frozen_string_literal: true

RSpec.describe 'VpsAdmin::API::Resources::OsTemplate' do
  before do
    header 'Accept', 'application/json'
    SpecSeed.admin
    SpecSeed.user
    SpecSeed.os_family
    SpecSeed.os_template
    SpecSeed.location
    SpecSeed.node
  end

  def index_path
    vpath('/os_templates')
  end

  def show_path(id)
    vpath("/os_templates/#{id}")
  end

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def json_post(path, payload)
    post path, JSON.dump(payload), { 'CONTENT_TYPE' => 'application/json' }
  end

  def json_put(path, payload)
    put path, JSON.dump(payload), { 'CONTENT_TYPE' => 'application/json' }
  end

  def json_delete(path)
    delete path, nil, { 'CONTENT_TYPE' => 'application/json' }
  end

  def os_templates
    json.dig('response', 'os_templates') || []
  end

  def os_template
    json.dig('response', 'os_template') || json['response']
  end

  def errors
    json.dig('response', 'errors') || json['errors'] || {}
  end

  def msg
    json['message'] || json.dig('response', 'message') || json['error']
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected #{code} for #{path}, got #{last_response.status}: #{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  def rid(value)
    value.is_a?(Hash) ? value['id'] : value
  end

  def create_template!(label:, os_family: SpecSeed.os_family, hypervisor_type: :vpsadminos,
                       cgroup_version: :cgroup_any, enabled: true, order: 1, enable_script: true,
                       enable_cloud_init: true, supported: true, manage_hostname: true,
                       manage_dns_resolver: true, config: {}, vendor: 'spec', variant: 'base',
                       arch: 'x86_64', distribution: 'specos', version: '1', info: nil)
    OsTemplate.create!(
      os_family: os_family,
      label: label,
      info: info,
      enabled: enabled,
      supported: supported,
      order: order,
      hypervisor_type: hypervisor_type,
      cgroup_version: cgroup_version,
      manage_hostname: manage_hostname,
      manage_dns_resolver: manage_dns_resolver,
      enable_script: enable_script,
      enable_cloud_init: enable_cloud_init,
      vendor: vendor,
      variant: variant,
      arch: arch,
      distribution: distribution,
      version: version,
      config: config
    )
  end

  def fixture(name)
    fixtures.fetch(name)
  end

  let!(:fixtures) do
    other_family = OsFamily.create!(label: 'Spec OS Other', description: 'other')

    {
      enabled_vpsadminos_a: create_template!(
        label: 'AAA vpsAdminOS',
        order: 1,
        cgroup_version: :cgroup_any
      ),
      enabled_vpsadminos_b: create_template!(
        label: 'BBB vpsAdminOS',
        order: 2,
        cgroup_version: :cgroup_v2
      ),
      disabled_vpsadminos: create_template!(
        label: 'Disabled vpsAdminOS',
        enabled: false,
        order: 3
      ),
      enabled_openvz: create_template!(
        label: 'OpenVZ Template',
        hypervisor_type: :openvz,
        order: 1
      ),
      script_disabled: create_template!(
        label: 'No Script Template',
        enable_script: false
      ),
      cloudinit_disabled: create_template!(
        label: 'No CloudInit Template',
        enable_cloud_init: false
      ),
      other_family: other_family,
      other_family_template: create_template!(
        label: 'Other Family Template',
        os_family: other_family,
        order: 4
      ),
      openvz_node: Node.create!(
        name: 'spec-node-openvz',
        location: SpecSeed.location,
        role: :node,
        hypervisor_type: :openvz,
        ip_addr: '192.0.2.111',
        max_vps: 3,
        cpus: 2,
        total_memory: 2048,
        total_swap: 512,
        active: true
      )
    }
  end

  describe 'API description' do
    it 'includes os template endpoints' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)
      expect(scopes).to include(
        'os_template#index',
        'os_template#show',
        'os_template#create',
        'os_template#update',
        'os_template#delete'
      )
    end
  end

  describe 'Index' do
    it 'rejects unauthenticated access' do
      skip 'requests plugin makes os_template#index public in this setup'
      json_get index_path

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'lists only enabled templates for normal users' do
      as(SpecSeed.user) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)

      ids = os_templates.map { |row| row['id'] }
      expect(ids).to include(
        fixture(:enabled_vpsadminos_a).id,
        fixture(:enabled_vpsadminos_b).id
      )
      expect(ids).to include(fixture(:script_disabled).id, fixture(:cloudinit_disabled).id)
      expect(ids).not_to include(fixture(:disabled_vpsadminos).id)
    end

    it 'enforces the output whitelist for normal users' do
      as(SpecSeed.user) { json_get index_path }

      expect_status(200)
      row = os_templates.find { |item| item['id'] == fixture(:enabled_vpsadminos_a).id }

      expect(row).not_to be_nil
      expect(row).to include(
        'id',
        'name',
        'label',
        'info',
        'supported',
        'hypervisor_type',
        'cgroup_version',
        'vendor',
        'variant',
        'arch',
        'distribution',
        'version',
        'os_family',
        'enable_script',
        'enable_cloud_init'
      )
      expect(row.keys).not_to include(
        'enabled',
        'order',
        'manage_hostname',
        'manage_dns_resolver',
        'config'
      )
    end

    it 'allows admins to see disabled templates with full output' do
      as(SpecSeed.admin) { json_get index_path }

      expect_status(200)
      ids = os_templates.map { |row| row['id'] }
      expect(ids).to include(fixture(:disabled_vpsadminos).id)

      row = os_templates.find { |item| item['id'] == fixture(:enabled_vpsadminos_a).id }
      expect(row).to include('enabled')
    end

    it 'defaults to vpsadminos hypervisor' do
      as(SpecSeed.admin) { json_get index_path }

      expect_status(200)
      ids = os_templates.map { |row| row['id'] }
      expect(ids).not_to include(fixture(:enabled_openvz).id)
    end

    it 'filters by hypervisor_type' do
      as(SpecSeed.user) { json_get index_path, os_template: { hypervisor_type: 'openvz' } }

      expect_status(200)
      ids = os_templates.map { |row| row['id'] }
      expect(ids).to include(fixture(:enabled_openvz).id)
      expect(ids).not_to include(fixture(:enabled_vpsadminos_a).id)
    end

    it 'filters by cgroup_version' do
      as(SpecSeed.user) { json_get index_path, os_template: { cgroup_version: 'cgroup_v2' } }

      expect_status(200)
      ids = os_templates.map { |row| row['id'] }
      expect(ids).to include(fixture(:enabled_vpsadminos_b).id)
      expect(ids).not_to include(fixture(:enabled_vpsadminos_a).id)
    end

    it 'filters by enable_script' do
      as(SpecSeed.user) { json_get index_path, os_template: { enable_script: false } }

      expect_status(200)
      ids = os_templates.map { |row| row['id'] }
      expect(ids).to include(fixture(:script_disabled).id)
      expect(ids).not_to include(fixture(:enabled_vpsadminos_a).id)
    end

    it 'filters by enable_cloud_init' do
      as(SpecSeed.user) { json_get index_path, os_template: { enable_cloud_init: false } }

      expect_status(200)
      ids = os_templates.map { |row| row['id'] }
      expect(ids).to include(fixture(:cloudinit_disabled).id)
      expect(ids).not_to include(fixture(:enabled_vpsadminos_a).id)
    end

    it 'filters by location and hypervisor_type' do
      as(SpecSeed.user) do
        json_get index_path, os_template: { location: SpecSeed.location.id, hypervisor_type: 'openvz' }
      end

      expect_status(200)
      ids = os_templates.map { |row| row['id'] }
      expect(ids).to include(fixture(:enabled_openvz).id)
      expect(ids).not_to include(fixture(:enabled_vpsadminos_a).id)
    end

    it 'filters by os_family' do
      as(SpecSeed.user) do
        json_get index_path, os_template: { os_family: fixture(:other_family).id }
      end

      expect_status(200)
      ids = os_templates.map { |row| row['id'] }
      expect(ids).to eq([fixture(:other_family_template).id])
    end

    it 'orders by order and label' do
      as(SpecSeed.user) { json_get index_path }

      expect_status(200)
      ids = os_templates.map { |row| row['id'] }
      expected_ids = OsTemplate.where(
        enabled: true,
        hypervisor_type: :vpsadminos
      ).order(:order, :label).pluck(:id)
      expect(ids).to eq(expected_ids)
    end

    it 'supports limit pagination' do
      as(SpecSeed.user) { json_get index_path, os_template: { limit: 1 } }

      expect_status(200)
      expect(os_templates.length).to eq(1)
    end

    it 'supports from_id pagination' do
      boundary = OsTemplate.order(:id).first.id
      as(SpecSeed.admin) { json_get index_path, os_template: { from_id: boundary } }

      expect_status(200)
      ids = os_templates.map { |row| row['id'] }
      expect(ids).to all(be > boundary)
    end

    it 'returns total_count meta when requested for admins' do
      as(SpecSeed.admin) { json_get index_path, _meta: { count: true } }

      expect_status(200)
      expected = OsTemplate.where(hypervisor_type: :vpsadminos).count
      expect(json.dig('response', '_meta', 'total_count')).to eq(expected)
    end

    it 'returns total_count meta when requested for users' do
      as(SpecSeed.user) { json_get index_path, _meta: { count: true } }

      expect_status(200)
      expected = OsTemplate.where(enabled: true, hypervisor_type: :vpsadminos).count
      expect(json.dig('response', '_meta', 'total_count')).to eq(expected)
    end
  end

  describe 'Show' do
    it 'rejects unauthenticated access' do
      json_get show_path(SpecSeed.os_template.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'shows enabled template for users with restricted output' do
      as(SpecSeed.user) { json_get show_path(fixture(:enabled_vpsadminos_a).id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(os_template['id']).to eq(fixture(:enabled_vpsadminos_a).id)
      expect(os_template).to include('enabled')
      expect(os_template.keys).not_to include(
        'order',
        'manage_hostname',
        'manage_dns_resolver',
        'config'
      )
    end

    it 'shows disabled template for users' do
      as(SpecSeed.user) { json_get show_path(fixture(:disabled_vpsadminos).id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(os_template['enabled']).to be(false)
    end

    it 'includes full output for admins' do
      as(SpecSeed.admin) { json_get show_path(fixture(:enabled_vpsadminos_a).id) }

      expect_status(200)
      expect(os_template).to include('order', 'manage_hostname', 'manage_dns_resolver', 'config')
      expect(os_template['config']).to be_a(String)
    end

    it 'returns 404 for unknown id' do
      missing = OsTemplate.maximum(:id).to_i + 100
      as(SpecSeed.admin) { json_get show_path(missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Create' do
    let(:create_payload) do
      {
        os_template: {
          os_family: SpecSeed.os_family.id,
          label: 'Spec Created Template',
          vendor: 'spec',
          variant: 'custom',
          arch: 'x86_64',
          distribution: 'specos',
          version: '2',
          info: 'created',
          enabled: true,
          supported: false,
          order: 9,
          hypervisor_type: 'vpsadminos',
          cgroup_version: 'cgroup_v2',
          manage_hostname: false,
          manage_dns_resolver: false,
          enable_script: false,
          enable_cloud_init: false,
          config: "features:\n  foo: true\n"
        }
      }
    end

    it 'rejects unauthenticated access' do
      json_post index_path, create_payload

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) { json_post index_path, create_payload }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to create an os template' do
      as(SpecSeed.admin) { json_post index_path, create_payload }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(os_template['label']).to eq('Spec Created Template')
      expect(rid(os_template['os_family'])).to eq(SpecSeed.os_family.id)

      record = OsTemplate.find_by!(label: 'Spec Created Template')
      expect(record.name).not_to be_empty
      expect(record.os_family_id).to eq(SpecSeed.os_family.id)
      expect(record.config).to be_a(Hash)
      expect(record.config.dig('features', 'foo')).to be(true)
    end

    it 'returns validation errors for missing label' do
      payload = Marshal.load(Marshal.dump(create_payload))
      payload[:os_template].delete(:label)

      as(SpecSeed.admin) { json_post index_path, payload }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors.keys.map(&:to_s)).to include('label')
    end

    it 'returns validation errors for invalid hypervisor_type' do
      payload = Marshal.load(Marshal.dump(create_payload))
      payload[:os_template][:hypervisor_type] = 'nope'

      as(SpecSeed.admin) { json_post index_path, payload }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors.keys.map(&:to_s)).to include('hypervisor_type')
    end

    it 'returns validation errors for invalid config YAML' do
      payload = Marshal.load(Marshal.dump(create_payload))
      payload[:os_template][:config] = 'not: [valid'

      as(SpecSeed.admin) { json_post index_path, payload }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors.keys.map(&:to_s)).to include('config')
    end
  end

  describe 'Update' do
    let!(:to_update) do
      create_template!(label: 'Update Template', order: 5, enabled: true)
    end

    it 'rejects unauthenticated access' do
      json_put show_path(to_update.id), os_template: { label: 'Updated' }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) do
        json_put show_path(to_update.id), os_template: { label: 'Updated' }
      end

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to update an os template' do
      as(SpecSeed.admin) do
        json_put show_path(to_update.id), os_template: {
          label: 'Updated Template',
          enabled: false,
          supported: false,
          order: 8,
          enable_script: false,
          config: "features:\n  bar: true\n"
        }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(os_template['id']).to eq(to_update.id)
      expect(os_template['label']).to eq('Updated Template')

      record = to_update.reload
      expect(record.enabled).to be(false)
      expect(record.supported).to be(false)
      expect(record.order).to eq(8)
      expect(record.enable_script).to be(false)
      expect(record.config.dig('features', 'bar')).to be(true)
    end

    it 'returns validation errors for invalid hypervisor_type' do
      as(SpecSeed.admin) do
        json_put show_path(to_update.id), os_template: { hypervisor_type: 'nope' }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors.keys.map(&:to_s)).to include('hypervisor_type')
    end

    it 'returns validation errors for invalid config YAML' do
      as(SpecSeed.admin) do
        json_put show_path(to_update.id), os_template: { config: 'not: [valid' }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors.keys.map(&:to_s)).to include('config')
    end
  end

  describe 'Delete' do
    it 'rejects unauthenticated access' do
      json_delete show_path(fixture(:enabled_vpsadminos_a).id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) { json_delete show_path(fixture(:enabled_vpsadminos_a).id) }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to delete an unused template' do
      to_delete = create_template!(label: 'Delete Template', order: 7)

      as(SpecSeed.admin) { json_delete show_path(to_delete.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(OsTemplate.find_by(id: to_delete.id)).to be_nil
    end

    it 'refuses to delete templates that are in use' do
      in_use_template = create_template!(label: 'In Use Template', order: 6)
      ActiveRecord::Base.connection.execute(
        'INSERT INTO vpses (user_id, node_id, os_template_id, object_state) ' \
        "VALUES (#{SpecSeed.user.id}, #{SpecSeed.node.id}, #{in_use_template.id}, " \
        "#{Vps.object_states[:active]})"
      )

      as(SpecSeed.admin) { json_delete show_path(in_use_template.id) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(msg).to include('The OS template is in use')
      expect(OsTemplate.find_by(id: in_use_template.id)).not_to be_nil
    end

    it 'returns 404 for unknown id' do
      missing = OsTemplate.maximum(:id).to_i + 100
      as(SpecSeed.admin) { json_delete show_path(missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end
end
