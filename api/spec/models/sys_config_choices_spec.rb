# frozen_string_literal: true

require 'open3'
require 'rbconfig'

RSpec.describe SysConfig do
  around do |example|
    registry = described_class.choices_registry.dup
    labels = described_class.label_registry.dup
    example.run
  ensure
    described_class.choices_registry.replace(registry)
    described_class.label_registry.replace(labels)
  end

  def register(type = String, **opts)
    described_class.register(:spec_choices, :setting, type, **opts)
    described_class.find_by!(category: 'spec_choices', name: 'setting')
  end

  let(:choices) { { values: { '' => 'Empty', 'valid' => 'Valid' } } }

  it 'keeps empty-string choices distinct from nullable values' do
    cfg = register(choices:, default: '')
    expect(cfg.value).to eq('')
    expect(cfg.value_nullable).to be(true)
    expect(cfg.choices).to eq([{ value: '', label: 'Empty' }, { value: 'valid', label: 'Valid' }])
    cfg.update!(value: nil)
    expect(cfg.reload.value).to be_nil
  end

  it 'validates integer choices without accepting a string or float equivalent' do
    cfg = register(Integer, choices: { values: { 0 => 'Zero', 2 => 'Two' } }, default: 0, nullable: false)
    expect(cfg.value).to eq(0)
    ['0', 0.0, nil, 3].each do |value|
      expect { cfg.update!(value:) }.to raise_error(ActiveRecord::RecordInvalid)
      cfg.reload
    end
    cfg.update!(value: 2)
    expect(cfg.reload.value).to eq(2)
  end

  it 'localizes labels lazily with the declared English fallback' do
    label = VpsAdmin::API::I18n.message('spec.missing_choice_label', default: 'Default label')
    cfg = register(choices: { values: { 'valid' => label } }, default: 'valid')
    expect(::I18n.with_locale(:en) { cfg.choices.first[:label] }).to eq('Default label')
    expect(::I18n.with_locale(:cs) { cfg.choices.first[:label] }).to eq('Default label')
  end

  ['legacy', nil, 7].each do |legacy|
    it "preserves unsupported #{legacy.inspect} on registration and metadata-only saves" do
      cfg = described_class.create!(category: 'spec_choices', name: 'setting', data_type: 'String', value: legacy)
      register(choices:, default: 'valid', nullable: false,
               label: VpsAdmin::API::I18n.message('sysconfig.labels.core.api_url', default: 'API URL'))
      expect(cfg.reload.value).to eq(legacy)
      expect(cfg.label).to eq('API URL')
      expect(::I18n.with_locale(:cs) { cfg.display_label }).to eq('URL API')
      cfg.update!(description: 'Metadata only')
      expect(cfg.reload.value).to eq(legacy)
      cfg.update!(value: 'valid')
      expect(cfg.reload.value).to eq('valid')
    end
  end

  it 'replaces or removes declaration metadata without changing stored values' do
    cfg = register(choices:, default: 'valid')
    register(choices: { values: { 'new' => 'New' } }, default: 'new', nullable: false)
    expect(cfg.reload.value).to eq('valid')
    expect(cfg.choices).to eq([{ value: 'new', label: 'New' }])
    register(choices: nil)
    expect(cfg.choices).to be_nil
    expect(cfg.value_nullable).to be_nil
    cfg.update!(value: 'anything')
  end

  it 'rejects invalid declarations before creating a setting' do
    [
      [String, { choices: { values: {} } }],
      [String, { choices: { values: { 1 => 'Wrong type' } } }],
      [Integer, { choices: { values: { 9_007_199_254_740_992 => 'Too large' } } }],
      [Boolean, { choices: { values: { true => 'Unsupported type' } } }],
      [String, { choices:, localized: true }],
      [String, { choices:, nullable: 'false' }],
      [String, { choices: { values: { 'valid' => '' } } }],
      [String, { choices: { values: { 'valid' => -> { 'Callback' } } } }],
      [String, { choices:, default: 'missing' }],
      [String, { choices:, nullable: false }]
    ].each do |type, opts|
      expect { register(type, **opts) }.to raise_error(ArgumentError)
      expect(described_class.exists?(category: 'spec_choices', name: 'setting')).to be(false)
    end
  end

  it 'registers mode choices for every incident-policy category' do
    IncidentEscalation::RULES.each_value do |rule|
      cfg = described_class.find_by!(category: rule.category, name: 'mode')
      expect(cfg.choices.map { |choice| choice[:value] }).to eq(%w[observe notify enforce])
      expect(cfg.value_nullable).to be(false)
    end
  end

  it 'cold-loads existing mode declarations without changing stored values', :no_transaction do
    mode = described_class.create!(category: 'incident_policy_cold_registration', name: 'mode',
                                   data_type: 'String', value: 'retired-mode')
    warning = described_class.create!(category: 'incident_policy_cold_registration', name: 'warning_limit',
                                      data_type: 'Integer', value: nil)
    stop = described_class.create!(category: 'incident_policy_cold_registration', name: 'stop_limit',
                                   data_type: 'Integer', value: 0)

    begin
      script = <<~'RUBY'
        require 'active_record'
        require 'json'
        require File.expand_path('lib/vpsadmin/api/incident_policy')

        IncidentEscalation.configure do
          rule(:cold_registration) do
            labels en: 'Cold registration policy'
            limits warning: 2, stop: 4
            applies_if { false }
          end
        end

        abort 'SysConfig was already loaded' if Object.const_defined?(:SysConfig)
        ActiveRecord::Base.establish_connection(ENV.fetch('DATABASE_URL'))
        existing = ActiveRecord::Base.connection.select_value(
          "SELECT COUNT(*) FROM sysconfig WHERE category = 'incident_policy_cold_registration' AND name IN ('mode', 'warning_limit', 'stop_limit')"
        )
        abort 'Existing policy rows are required' unless existing.to_i == 3

        ActiveRecord::Base.transaction do
          require File.expand_path('lib/vpsadmin')
          mode = SysConfig.find_by!(category: 'incident_policy_cold_registration', name: 'mode')
          thresholds = %w[warning_limit stop_limit].to_h do |name|
            setting = SysConfig.find_by!(category: mode.category, name:)
            [name, { value: setting.value, label: setting.label,
                     czech_label: ::I18n.with_locale(:cs) { setting.display_label } }]
          end
          result = { value: mode.value, choices: mode.choice_contract.fetch(:values).keys,
                     nullable: mode.value_nullable, label: mode.label,
                     czech_label: ::I18n.with_locale(:cs) { mode.display_label }, thresholds: }
          puts "SYSCONFIG_COLD_LOAD=#{JSON.generate(result)}"
          raise ActiveRecord::Rollback
        end
      RUBY
      stdout, stderr, status = Open3.capture3(
        { 'RACK_ENV' => 'test' }, RbConfig.ruby, '-rbundler/setup', '-e', script,
        chdir: File.expand_path('../..', __dir__)
      )

      expect(status.success?).to be(true), "#{stdout}\n#{stderr}"
      result = stdout.lines.find { |line| line.start_with?('SYSCONFIG_COLD_LOAD=') }
      expect(result).not_to be_nil
      expect(JSON.parse(result.delete_prefix('SYSCONFIG_COLD_LOAD='))).to eq(
        'value' => 'retired-mode', 'choices' => %w[observe notify enforce], 'nullable' => false,
        'label' => 'Global policy mode', 'czech_label' => 'Globální režim pravidla',
        'thresholds' => {
          'warning_limit' => { 'value' => nil, 'label' => 'Global warning threshold (7 days)',
                               'czech_label' => 'Globální limit pro upozornění (7 dní)' },
          'stop_limit' => { 'value' => 0, 'label' => 'Global shutdown threshold (30 days)',
                            'czech_label' => 'Globální limit pro vypnutí (30 dní)' }
        }
      )
    ensure
      mode.delete
      warning&.delete
      stop&.delete
    end
  end
end
