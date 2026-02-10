# frozen_string_literal: true

require 'yaml'

RSpec.describe 'VpsAdmin::API' do
  describe 'Custom route coverage' do
    it 'ensures all known custom routes are listed as covered' do
      known = [
        'GET /metrics'
      ]

      covered_path = File.join(__dir__, 'covered_custom_routes.yml')
      covered_yaml = YAML.load_file(covered_path) || {}
      covered = Array(covered_yaml['covered_custom_routes']).map(&:to_s)

      missing = known - covered
      extra = covered - known

      aggregate_failures 'custom route coverage manifests' do
        expect(missing).to eq([]), "Missing custom routes:\n#{missing.join("\n")}"
        expect(extra).to eq([]), "Unknown custom routes listed:\n#{extra.join("\n")}"
      end
    end
  end
end
