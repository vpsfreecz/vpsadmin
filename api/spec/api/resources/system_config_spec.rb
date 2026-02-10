# frozen_string_literal: true

require 'yaml'

RSpec.describe 'VpsAdmin::API::Resources::SystemConfig' do
  let(:category) { 'spec' }
  let(:other_category) { 'spec_other' }

  before do
    header 'Accept', 'application/json'

    SysConfig.create!(
      category:,
      name: 'public',
      data_type: 'String',
      value: 'pub',
      label: 'Public',
      description: 'Visible to unauthenticated users',
      min_user_level: 0
    )

    SysConfig.create!(
      category:,
      name: 'user_only',
      data_type: 'String',
      value: 'u',
      label: 'User only',
      description: 'Visible to users',
      min_user_level: 1
    )

    SysConfig.create!(
      category:,
      name: 'support_only',
      data_type: 'String',
      value: 's',
      label: 'Support only',
      description: 'Visible to support',
      min_user_level: 21
    )

    SysConfig.create!(
      category:,
      name: 'admin_only',
      data_type: 'String',
      value: 'a',
      label: 'Admin only',
      description: 'Visible to admin',
      min_user_level: 99
    )

    SysConfig.create!(
      category:,
      name: 'hidden',
      data_type: 'String',
      value: 'h',
      label: 'Hidden',
      description: 'Never visible',
      min_user_level: nil
    )

    SysConfig.create!(
      category:,
      name: 'array_value',
      data_type: 'Array',
      value: ['x'],
      label: 'Array value',
      description: 'Visible to unauthenticated users',
      min_user_level: 0
    )

    SysConfig.create!(
      category: other_category,
      name: 'public_other',
      data_type: 'String',
      value: 'other',
      label: 'Other category',
      description: 'Visible in other category',
      min_user_level: 0
    )
  end

  def index_path
    vpath('/system_configs')
  end

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def json_put(path, payload)
    put path, JSON.dump(payload), {
      'CONTENT_TYPE' => 'application/json'
    }
  end

  def show_path(name)
    vpath("/system_configs/#{category}/#{name}")
  end

  def update_path(name)
    show_path(name)
  end

  def system_configs
    json.dig('response', 'system_configs')
  end

  def system_config
    json.dig('response', 'system_config')
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected status #{code} for #{path}, got #{last_response.status} body=#{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  describe 'Index' do
    it 'shows only public config for unauthenticated users' do
      json_get index_path, system_config: { category: category }

      expect_status(200)
      names = system_configs.map { |cfg| cfg['name'] }
      expect(names).to eq(%w[array_value public])
      expect(names).to eq(names.sort)

      public_cfg = system_configs.find { |cfg| cfg['name'] == 'public' }
      expect(public_cfg['type']).to eq('String')
      expect(public_cfg['value']).to eq('pub')
      expect(public_cfg['min_user_level']).to eq(0)

      array_cfg = system_configs.find { |cfg| cfg['name'] == 'array_value' }
      expect(array_cfg['type']).to eq('Array')
      expect(YAML.safe_load(array_cfg['value'])).to eq(['x'])
    end

    it 'shows user config for normal users' do
      as(SpecSeed.user) { json_get index_path, system_config: { category: category } }

      expect_status(200)
      names = system_configs.map { |cfg| cfg['name'] }
      expect(names).to eq(%w[array_value public user_only])
    end

    it 'shows support config for support' do
      as(SpecSeed.support) { json_get index_path, system_config: { category: category } }

      expect_status(200)
      names = system_configs.map { |cfg| cfg['name'] }
      expect(names).to eq(%w[array_value public support_only user_only])
    end

    it 'shows admin config for admin' do
      as(SpecSeed.admin) { json_get index_path, system_config: { category: category } }

      expect_status(200)
      names = system_configs.map { |cfg| cfg['name'] }
      expect(names).to eq(%w[admin_only array_value public support_only user_only])
      expect(names).not_to include('hidden')
    end

    it 'filters by category' do
      json_get index_path, system_config: { category: other_category }

      expect_status(200)
      names = system_configs.map { |cfg| cfg['name'] }
      expect(names).to eq(['public_other'])
    end
  end

  describe 'Show' do
    it 'allows unauthenticated access to public config' do
      json_get show_path('public')

      expect_status(200)
      expect(system_config['name']).to eq('public')
    end

    it 'rejects unauthenticated access to user-only config' do
      json_get show_path('user_only')

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows users to access user-only config' do
      as(SpecSeed.user) { json_get show_path('user_only') }

      expect_status(200)
      expect(system_config['name']).to eq('user_only')
    end

    it 'rejects users from accessing support-only config' do
      as(SpecSeed.user) { json_get show_path('support_only') }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows support to access support-only config' do
      as(SpecSeed.support) { json_get show_path('support_only') }

      expect_status(200)
      expect(system_config['name']).to eq('support_only')
    end

    it 'rejects support from accessing admin-only config' do
      as(SpecSeed.support) { json_get show_path('admin_only') }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows admin to access admin-only config' do
      as(SpecSeed.admin) { json_get show_path('admin_only') }

      expect_status(200)
      expect(system_config['name']).to eq('admin_only')
    end

    it 'does not allow admin access to hidden config' do
      as(SpecSeed.admin) { json_get show_path('hidden') }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'returns 404 for unknown config' do
      json_get show_path('does_not_exist')

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Update' do
    it 'rejects unauthenticated updates' do
      json_put update_path('public'), system_config: { value: 'changed' }

      expect_status(401)
    end

    it 'rejects user updates' do
      as(SpecSeed.user) { json_put update_path('public'), system_config: { value: 'changed' } }

      expect_status(403)
    end

    it 'rejects support updates' do
      as(SpecSeed.support) { json_put update_path('public'), system_config: { value: 'changed' } }

      expect_status(403)
    end

    it 'allows admin to update string values' do
      as(SpecSeed.admin) { json_put update_path('public'), system_config: { value: 'changed' } }

      expect_status(200)
      expect(system_config['name']).to eq('public')
      expect(system_config['value']).to eq('changed')
      expect(system_config['type']).to eq('String')

      cfg = SysConfig.find_by!(category: category, name: 'public')
      expect(cfg.value).to eq('changed')
    end

    it 'allows admin to update array values with YAML' do
      yaml = "- a\n- b\n"
      as(SpecSeed.admin) { json_put update_path('array_value'), system_config: { value: yaml } }

      expect_status(200)
      expect(system_config['type']).to eq('Array')
      expect(YAML.safe_load(system_config['value'])).to eq(%w[a b])

      cfg = SysConfig.find_by!(category: category, name: 'array_value')
      expect(cfg.value).to eq(%w[a b])
    end

    it 'returns 404 for unknown config' do
      as(SpecSeed.admin) { json_put update_path('nope'), system_config: { value: 'x' } }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end
end
