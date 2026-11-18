require 'spec_helper'

RSpec.describe IncidentEscalation do
  def declaration(key = 'example', warning: 5, stop: 10, &selector)
    builder = described_class::RuleBuilder.new(key)
    builder.labels en: 'Example policy', cs: 'Zkušební pravidlo'
    builder.limits(warning:, stop:)
    builder.applies_if(&selector) if selector
    builder.build
  end

  it 'accepts several policies without an adapter without a special required key' do
    config = described_class::Configuration.new
    %w[alpha beta].each do |key|
      config.rule(key) do
        labels en: key
        limits warning: 5, stop: 10
      end
    end
    expect(config.rules.keys).to eq(%w[alpha beta])
    expect(config.rules.values.flat_map { |rule| rule.metadata.keys }).not_to include('source_type')
  end

  it 'validates existing category-compatible keys and collation-safe uniqueness' do
    expect(declaration('a' * 59).key).to eq('a' * 59)
    ['a' * 60, 'has-dash', '', 'has space'].each do |key|
      expect { declaration(key) }.to raise_error(described_class::InvalidConfiguration)
    end
    config = described_class::Configuration.new
    config.rule(:Case) do
      labels en: 'Case'
      limits warning: 1, stop: 2
    end
    expect { config.rule(:case) { labels en: 'collision' } }.to raise_error(described_class::InvalidConfiguration, /Duplicate/)
  end

  it 'rejects obsolete adapter options, unordered or missing limits, malformed templates and obsolete callbacks' do
    expect { described_class::Configuration.new.rule(:manual, adapter: :node_oomd) }.to raise_error(ArgumentError)
    [[0, 10], [11, 10], [1.5, 2], [1, 2_147_483_648]].each do |warning, stop|
      expect { declaration(warning:, stop:) }.to raise_error(described_class::InvalidConfiguration)
    end
    expect(described_class::RULES).to be_empty
    builder = described_class::RuleBuilder.new(:test)
    builder.labels en: 'Test'
    expect { builder.build }.to raise_error(described_class::InvalidConfiguration)
    builder.limits warning: 1, stop: 2
    builder.templates warning: :'../mail', stopped: :valid
    expect { builder.build }.to raise_error(described_class::InvalidConfiguration)
    expect(builder).not_to respond_to(:policy)
  end
end
