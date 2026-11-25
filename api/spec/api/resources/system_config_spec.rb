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

  describe 'localized setting labels' do
    around do |example|
      registry = SysConfig.label_registry.dup
      example.run
    ensure
      SysConfig.label_registry.replace(registry)
      header 'Accept-Language', nil
    end

    it 'uses each request language in Index, Show and Update without changing stored labels or values' do
      SysConfig.register(category, :public, String,
                         label: VpsAdmin::API::I18n.message('sysconfig.labels.core.api_url', default: 'API URL'))

      { 'en' => 'API URL', 'cs' => 'URL API' }.each do |language, label|
        header 'Accept-Language', language
        json_get index_path, system_config: { category: }
        expect_status(200)
        expect(system_configs.find { |row| row['name'] == 'public' }).to include('label' => label, 'value' => 'pub')
        expect(system_configs.map { |row| row['name'] }).not_to include('hidden')

        json_get show_path('public')
        expect_status(200)
        expect(system_config).to include('label' => label, 'value' => 'pub', 'localized' => false)

        as(SpecSeed.admin) { json_put update_path('public'), system_config: { value: 'pub' } }
        expect_status(200)
        expect(system_config).to include('label' => label, 'value' => 'pub', 'localized' => false)
        expect(SysConfig.find_by!(category:, name: 'public').label).to eq('API URL')
      end
    end
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
      expect(public_cfg['localized']).to be(false)
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

    it 'returns localized_value for localized hash settings' do
      SysConfig.create!(
        category:,
        name: 'localized',
        data_type: 'Hash',
        localized: true,
        value: { 'en' => 'English value', 'cs' => 'Czech value' },
        label: 'Localized',
        description: 'Localized setting',
        min_user_level: 0
      )

      header 'Accept-Language', 'cs'
      json_get show_path('localized')
      header 'Accept-Language', nil

      expect_status(200)
      expect(system_config['type']).to eq('Hash')
      expect(system_config['localized']).to be(true)
      expect(YAML.safe_load(system_config['value'])).to eq(
        'en' => 'English value',
        'cs' => 'Czech value'
      )
      expect(system_config['localized_value']).to eq('Czech value')
    end

    it 'does not localize ordinary hash settings' do
      SysConfig.create!(
        category:,
        name: 'plain_hash',
        data_type: 'Hash',
        value: { 'EUR' => 25.0, 'USD' => 23.0 },
        label: 'Plain hash',
        description: 'Structural hash setting',
        min_user_level: 0
      )

      header 'Accept-Language', 'cs'
      json_get show_path('plain_hash')
      header 'Accept-Language', nil

      expect_status(200)
      expect(system_config['type']).to eq('Hash')
      expect(system_config['localized']).to be(false)
      expect(YAML.safe_load(system_config['value'])).to eq(
        'EUR' => 25.0,
        'USD' => 23.0
      )
      expect(system_config['localized_value']).to be_nil
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

  describe 'evidence reporting checkbox', :evidence_checkbox do
    let(:enabled_config) { SysConfig.find_by!(category: 'vps_evidence_rtnl_latency', name: 'enabled') }
    let(:enabled_path) { vpath('/system_configs/vps_evidence_rtnl_latency/enabled') }

    it 'persists canonical editor strings as booleans when enabling and disabling' do
      { '1' => true, '0' => false }.each do |value, expected|
        as(SpecSeed.admin) { json_put enabled_path, system_config: { value: } }

        expect_status(200)
        expect(json['status']).to be(true)
        expect(system_config['value']).to be(expected)
        expect(enabled_config.reload.value).to be(expected)
        expect(VpsEvidence.config('rtnl_latency')[:enabled]).to be(expected)
      end
    end

    it 'preserves real booleans and null inheritance' do
      [true, false, nil].each do |value|
        as(SpecSeed.admin) { json_put enabled_path, system_config: { value: } }

        expect_status(200)
        expect(json['status']).to be(true)
        expect(system_config['value']).to eql(value)
        expect(enabled_config.reload.value).to eql(value)
        expect(VpsEvidence.config('rtnl_latency')[:enabled]).to be(value || false)
      end
    end

    it 'rejects noncanonical strings and integers without changing the current switch' do
      enabled_config.update!(value: true)
      ['true', 'false', '01', 1].each do |value|
        as(SpecSeed.admin) { json_put enabled_path, system_config: { value: } }

        expect_status(200)
        expect(json['status']).to be(false)
        expect(json.dig('errors', 'value')).not_to be_nil
        expect(enabled_config.reload.value).to be(true)
        expect(VpsEvidence.config('rtnl_latency')[:enabled]).to be(true)
      end
    end

    it 'keeps unrelated Boolean strings and nested YAML values unchanged' do
      ordinary = SysConfig.create!(category:, name: 'ordinary_checkbox', data_type: 'Boolean', value: false, min_user_level: 99)
      %w[1 0].each do |value|
        as(SpecSeed.admin) { json_put update_path(ordinary.name), system_config: { value: } }

        expect_status(200)
        expect(json['status']).to be(true)
        expect(system_config['value']).to eql(value)
        expect(ordinary.reload.value).to eql(value)
      end

      values = [false, 0, '', nil, { 'enabled' => '1' }]
      as(SpecSeed.admin) { json_put update_path('array_value'), system_config: { value: YAML.dump(values) } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(YAML.safe_load(system_config['value'])).to eq(values)
      expect(SysConfig.find_by!(category:, name: 'array_value').value).to eq(values)
    end
  end

  describe 'ordinary value preservation' do
    it 'keeps scalar types through the real cleaner and persistence without choices' do
      {
        'String' => ['text', " text\n", '0', '', " \t\n ", nil],
        'Text' => ["line one\nline two", '', nil],
        'Integer' => [0, 23, -7, '0', '-7', nil],
        'Float' => [0.0, 1.25, -2.5, '1.25', nil],
        'Boolean' => [false, true, '0', '1', nil],
        'Custom' => [false, true, 0, -3, 1.25, '', nil, [], {},
                     { 'items' => [false, 0, '', nil, { 'key' => 'value' }] }]
      }.each do |type, values|
        cfg = SysConfig.create!(category:, name: "ordinary_#{type.downcase}", data_type: type,
                                value: 'before', min_user_level: 99)

        values.each do |value|
          as(SpecSeed.admin) { json_put update_path(cfg.name), system_config: { value: } }
          expected = value.is_a?(String) && value.strip.empty? ? nil : value

          expect_status(200)
          expect(json['status']).to be(true), "#{type} update failed"
          expect(cfg.reload.value).to eql(expected), "#{type} changed scalar identity"
          expect(system_config['value']).to eql(expected)
        end
      end
    end

    it 'parses Array and Hash YAML while preserving nested values and YAML null' do
      {
        'Array' => [[], [false, true, 0, -3, 1.25, '', nil, { 'key' => 'value' }], nil],
        'Hash' => [{}, { 'false' => false, 'zero' => 0, 'empty' => '', 'unset' => nil,
                         'nested' => [1.25, { 'key' => 'value' }] }, nil]
      }.each do |type, values|
        cfg = SysConfig.create!(category:, name: "ordinary_#{type.downcase}", data_type: type,
                                value: nil, min_user_level: 99)

        values.each do |value|
          # Textarea form submissions can use CRLF instead of the API's LF.
          [YAML.dump(value), YAML.dump(value).gsub("\n", "\r\n")].each do |yaml|
            as(SpecSeed.admin) { json_put update_path(cfg.name), system_config: { value: yaml } }

            expect_status(200)
            expect(json['status']).to be(true)
            expect(cfg.reload.value).to eql(value)
            expect(YAML.safe_load(system_config['value'])).to eql(value)
          end
        end
      end
    end

    it 'retains the existing omitted scalar reset and rejects invalid encoding before writes' do
      cfg = SysConfig.find_by!(category:, name: 'public')
      as(SpecSeed.admin) { json_put update_path(cfg.name), system_config: {} }
      expect_status(200)
      expect(json['status']).to be(true)
      expect(cfg.reload.value).to be_nil

      cfg.update!(value: 'retained')
      allow(SysConfig).to receive(:find_by!).and_call_original
      invalid_json = "{\"system_config\":{\"value\":\"\xFF\"}}".dup.force_encoding(Encoding::UTF_8)
      as(SpecSeed.admin) { put update_path(cfg.name), invalid_json, { 'CONTENT_TYPE' => 'application/json' } }

      expect(json['status']).to be(false)
      expect(SysConfig).not_to have_received(:find_by!)
      expect(cfg.reload.value).to eq('retained')
    end
  end

  describe 'declared choices' do
    def expect_invalid_choice
      expect_status(200)
      expect(json['status']).to be(false)
      expect(json.dig('errors', 'value')).to include('is not included in the list')
    end

    around do |example|
      registry = SysConfig.choices_registry.dup
      example.run
    ensure
      SysConfig.choices_registry.replace(registry)
      header 'Accept-Language', nil
    end

    before do
      SysConfig.register(category, :choice, String, default: 'first', min_user_level: 0, nullable: false,
                                                    choices: { values: {
                                                     'first' => VpsAdmin::API::I18n.message('sysconfig.choices.incident_mode.observe', default: 'Observation only'),
                                                     '' => 'Empty',
                                                     '  ' => 'Spaces'
                                                   } })
      SysConfig.register(category, :integer_choice, Integer, default: 0, min_user_level: 99,
                                                             choices: { values: { 0 => 'Zero', 2 => 'Two' } })
    end

    it 'adds typed metadata to public reads without exposing private settings' do
      json_get index_path, system_config: { category: }
      expect_status(200)
      row = system_configs.find { |cfg| cfg['name'] == 'choice' }
      expect(row['choices']).to eq([{ 'value' => 'first', 'label' => 'Observation only' }, { 'value' => '', 'label' => 'Empty' }, { 'value' => '  ', 'label' => 'Spaces' }])
      expect(row['value_nullable']).to be(false)
      expect(system_configs.map { |cfg| cfg['name'] }).not_to include('integer_choice')
      expect(system_configs.find { |cfg| cfg['name'] == 'public' }).to include('choices' => nil, 'value_nullable' => nil)
    end

    it 'uses the explicit request language for labels and falls back to English' do
      header 'Accept-Language', 'cs'
      as(SpecSeed.admin) { json_get show_path('choice') }
      expect_status(200)
      expect(system_config['choices'].first['label']).to eq('Pouze sledování')
      header 'Accept-Language', 'unsupported'
      as(SpecSeed.admin) { json_get show_path('choice') }
      expect_status(200)
      expect(system_config['choices'].first['label']).to eq('Observation only')
    end

    it 'preserves integer zero and explicit nullable resets through Update' do
      as(SpecSeed.admin) { json_put update_path('integer_choice'), system_config: { value: 2 } }
      expect_status(200)
      expect(system_config).to include('value' => 2, 'value_nullable' => true)
      expect(system_config['choices']).to eq([{ 'value' => 0, 'label' => 'Zero' }, { 'value' => 2, 'label' => 'Two' }])
      as(SpecSeed.admin) { json_put update_path('integer_choice'), system_config: { value: nil } }
      expect_status(200)
      expect(system_config['value']).to be_nil
      as(SpecSeed.admin) { json_put update_path('integer_choice'), system_config: { value: 0 } }
      expect_status(200)
      expect(system_config['value']).to eq(0)
    end

    it 'allows the empty string while rejecting undeclared values, types and forbidden null' do
      ['', '  '].each do |value|
        as(SpecSeed.admin) { json_put update_path('choice'), system_config: { value: } }
        expect_status(200)
        expect(json['status']).to be(true)
        expect(SysConfig.find_by!(category:, name: 'choice').value).to eq(value)
      end
      ['missing', 0, nil].each do |value|
        as(SpecSeed.admin) { json_put update_path('choice'), system_config: { value: } }
        expect_invalid_choice
        expect(SysConfig.find_by!(category:, name: 'choice').value).to eq('  ')
      end
      as(SpecSeed.admin) { json_put update_path('integer_choice'), system_config: { value: '0' } }
      expect_invalid_choice
    end

    it 'keeps the existing empty and whitespace reset behavior for settings without choices' do
      ['', '  '].each do |value|
        as(SpecSeed.admin) { json_put update_path('public'), system_config: { value: } }
        expect_status(200)
        expect(json['status']).to be(true)
        expect(SysConfig.find_by!(category:, name: 'public').value).to be_nil
      end
      as(SpecSeed.admin) { json_put update_path('public'), system_config: {} }
      expect_status(200)
      expect(json['status']).to be(true)
      expect(SysConfig.find_by!(category:, name: 'public').value).to be_nil
    end

    it 'keeps malformed string encoding inside framework field validation' do
      parameters = VpsAdmin::API::Resources::SystemConfig::Update.input.clone
      parameters.params.map!(&:dup)
      parameters.exec if parameters.params.empty?
      values = { value: "\xFF".dup.force_encoding(Encoding::UTF_8) }
      payload = parameters.namespace ? { parameters.namespace => values } : values

      expect do
        parameters.validate(payload)
      end.to raise_error(HaveAPI::ValidationError) { |error|
        expect(error.to_hash.keys).to eq([:value])
        expect(error.to_hash[:value].first.key).to eq('haveapi.validation.invalid_string_encoding')
      }
    end

    it 'returns unsupported stored values but rejects an explicit unchanged invalid write' do
      cfg = SysConfig.find_by!(category:, name: 'choice')
      cfg.update_column(:value, 'legacy')
      json_get show_path('choice')
      expect_status(200)
      expect(system_config['value']).to eq('legacy')
      as(SpecSeed.admin) { json_put update_path('choice'), system_config: { value: 'legacy' } }
      expect_invalid_choice
      expect(cfg.reload.value).to eq('legacy')
    end
  end
end
