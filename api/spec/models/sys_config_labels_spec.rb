# frozen_string_literal: true

RSpec.describe SysConfig do
  around do |example|
    registry = described_class.label_registry.dup
    example.run
  ensure
    described_class.label_registry.replace(registry)
  end

  let(:message) do
    VpsAdmin::API::I18n.message('sysconfig.labels.core.api_url', default: 'API URL')
  end

  def register(**opts)
    described_class.register(:spec_labels, :setting, String, **opts)
    described_class.find_by!(category: 'spec_labels', name: 'setting')
  end

  it 'stores the English default while localizing each display independently' do
    cfg = ::I18n.with_locale(:cs) { register(label: message, default: 'unchanged') }
    expect(cfg.label).to eq('API URL')
    expect(::I18n.with_locale(:cs) { cfg.display_label }).to eq('URL API')
    expect(::I18n.with_locale(:en) { cfg.display_label }).to eq('API URL')
    expect(cfg.reload.value).to eq('unchanged')
    expect(cfg.localized).to be(false)
  end

  it 'preserves custom, empty and missing stored labels without a declaration' do
    cfg = described_class.create!(category: 'spec_labels', name: 'external', data_type: 'String')
    ['Custom label', '', nil].each do |label|
      cfg.update!(label:)
      expect(::I18n.with_locale(:cs) { cfg.display_label }).to eq(label)
    end
  end

  it 'clears localized metadata when registered again with plain or omitted labels' do
    cfg = register(label: message)
    register(label: 'Custom label')
    expect(::I18n.with_locale(:cs) { cfg.reload.display_label }).to eq('Custom label')
    register(label: message)
    register
    expect(::I18n.with_locale(:cs) { cfg.reload.display_label }).to eq('API URL')
  end

  it 'requires a nonempty English default for localized declarations' do
    [nil, '', ' '].each do |default|
      invalid = VpsAdmin::API::I18n.message('spec.missing_label', default:)
      expect { register(label: invalid) }.to raise_error(ArgumentError)
    end
    expect(described_class.exists?(category: 'spec_labels', name: 'setting')).to be(false)
  end

  it 'labels every bundled static setting and each configured policy field in both languages' do
    english = ::I18n.t('vpsadmin.sysconfig.labels', locale: :en)
    czech = ::I18n.t('vpsadmin.sysconfig.labels', locale: :cs)
    static = english.except(:incident_policy)
    static = static.slice(:core, :node, :dns) if ENV['VPSADMIN_PLUGINS'] == 'none'
    expect(static.fetch(:core)).not_to have_key(:logo_url)
    expect(static.values.sum(&:length)).to eq(ENV['VPSADMIN_PLUGINS'] == 'none' ? 14 : 33)

    static.each do |category, settings|
      settings.each do |name, label|
        cfg = described_class.find_by!(category:, name:)
        expect(cfg.label).to eq(label)
        expect(::I18n.with_locale(:cs) { cfg.display_label }).to eq(czech.fetch(category).fetch(name))
      end
    end

    IncidentEscalation::RULES.each_value do |rule|
      english.fetch(:incident_policy).each do |name, label|
        cfg = described_class.find_by!(category: rule.category, name:)
        expect(cfg.label).to eq(label)
        expect(::I18n.with_locale(:cs) { cfg.display_label }).to eq(czech.fetch(:incident_policy).fetch(name))
      end
    end
  end
end
