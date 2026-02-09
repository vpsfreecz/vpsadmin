# frozen_string_literal: true

require 'yaml'
require 'fileutils'

RSpec.describe EndpointInventory, :generator do
  describe 'Generate pending endpoints' do
    it 'writes spec/api/pending_endpoints.yml' do
      all_scopes = described_class.all_scopes(self, only_first_version: true)

      covered_path = File.join(__dir__, 'covered_endpoints.yml')
      pending_path = File.join(__dir__, 'pending_endpoints.yml')

      covered_yaml = YAML.load_file(covered_path) || {}
      covered = Array(covered_yaml['covered']).map(&:to_s)

      pending = (all_scopes - covered).sort

      FileUtils.mkdir_p(File.dirname(pending_path))
      File.write(pending_path, { 'pending' => pending }.to_yaml)

      written = YAML.load_file(pending_path)
      expect(written).to eq('pending' => pending)
    end
  end
end
