# frozen_string_literal: true

require 'yaml'

RSpec.describe EndpointInventory do
  describe 'API endpoint coverage' do
    it 'ensures all endpoints are listed in covered or pending' do
      all_scopes = described_class.all_scopes(self, only_first_version: true)

      covered_path = File.join(__dir__, 'covered_endpoints.yml')
      pending_path = File.join(__dir__, 'pending_endpoints.yml')

      covered_yaml = YAML.load_file(covered_path) || {}
      pending_yaml = YAML.load_file(pending_path) || {}

      covered = Array(covered_yaml['covered']).map(&:to_s)
      pending = Array(pending_yaml['pending']).map(&:to_s)

      known = (covered + pending).uniq

      missing = all_scopes - known
      stale = known - all_scopes

      aggregate_failures 'endpoint coverage manifests' do
        expect(missing).to eq([]), "Missing scopes:\n#{missing.join("\n")}"
        expect(stale).to eq([]), "Stale scopes:\n#{stale.join("\n")}"
      end
    end
  end
end
