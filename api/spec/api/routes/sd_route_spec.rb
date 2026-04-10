# frozen_string_literal: true

require 'json'

RSpec.describe 'VpsAdmin::API::ServiceDiscovery' do
  def set_sysconfig(category:, name:, data_type:, value:)
    cfg = SysConfig.find_or_initialize_by(category:, name:)
    cfg.data_type = data_type
    cfg.value = value
    cfg.save! if cfg.changed?
  end

  def ensure_snapshot_download_base_url!
    SnapshotDownload.remove_instance_variable(:@base_url) if SnapshotDownload.instance_variable_defined?(:@base_url)

    set_sysconfig(
      category: 'core',
      name: 'snapshot_download_base_url',
      data_type: 'String',
      value: 'https://downloads.example.test/backup'
    )
  end

  def configure_download_pool_sd!(allowed_networks:, trusted_proxies: [])
    set_sysconfig(
      category: 'monitoring',
      name: 'download_pool_sd_allowed_networks',
      data_type: 'Array',
      value: allowed_networks
    )
    set_sysconfig(
      category: 'monitoring',
      name: 'download_pool_sd_trusted_proxies',
      data_type: 'Array',
      value: trusted_proxies
    )
  end

  describe 'GET /sd/download-pools' do
    let(:pool) { SpecSeed.pool }
    let(:other_pool) { SpecSeed.other_pool }

    def request_download_pool_sd(env = {})
      get '/sd/download-pools', nil, env
    end

    def parsed_response
      JSON.parse(last_response.body)
    end

    before do
      ensure_snapshot_download_base_url!
      configure_download_pool_sd!(allowed_networks: [], trusted_proxies: [])
    end

    it 'rejects access when the client IP is not allowed' do
      request_download_pool_sd(
        'REMOTE_ADDR' => '198.51.100.10'
      )

      expect(last_response.status).to eq(403)
      expect(last_response.body).to include('Access denied')
    end

    it 'allows direct access from an allowed network' do
      configure_download_pool_sd!(allowed_networks: ['198.51.100.0/24'])

      request_download_pool_sd(
        'REMOTE_ADDR' => '198.51.100.10'
      )

      expect(last_response.status).to eq(200)
      expect(last_response.headers['Content-Type']).to include('application/json')

      response = parsed_response
      pool_ids = response.map { |entry| entry.dig('labels', 'pool_id') }
      target = response.detect { |entry| entry.dig('labels', 'pool_id') == pool.id.to_s }

      expect(pool_ids).to contain_exactly(pool.id.to_s, other_pool.id.to_s)
      expect(target['targets']).to eq(
        ["https://downloads.example.test/backup/#{pool.node.fqdn}/#{pool.id}/_vpsadmin-download-healthcheck"]
      )
      expect(target['labels']).to include(
        'node_fqdn' => pool.node.fqdn,
        'node_name' => pool.node.domain_name,
        'pool_name' => pool.name,
        'pool_role' => pool.role
      )
    end

    it 'excludes pools on inactive nodes' do
      configure_download_pool_sd!(allowed_networks: ['198.51.100.0/24'])
      other_pool.node.update!(active: false)

      request_download_pool_sd(
        'REMOTE_ADDR' => '198.51.100.10'
      )

      expect(last_response.status).to eq(200)

      pool_ids = parsed_response.map { |entry| entry.dig('labels', 'pool_id') }

      expect(pool_ids).to contain_exactly(pool.id.to_s)
      expect(pool_ids).not_to include(other_pool.id.to_s)
    end

    it 'allows access through a trusted proxy' do
      configure_download_pool_sd!(
        allowed_networks: ['198.51.100.0/24'],
        trusted_proxies: ['203.0.113.0/24']
      )

      request_download_pool_sd(
        'REMOTE_ADDR' => '203.0.113.20',
        'HTTP_X_REAL_IP' => '198.51.100.10'
      )

      expect(last_response.status).to eq(200)
    end

    it 'rejects forwarded addresses from untrusted proxies' do
      configure_download_pool_sd!(allowed_networks: ['198.51.100.0/24'])

      request_download_pool_sd(
        'REMOTE_ADDR' => '203.0.113.20',
        'HTTP_X_REAL_IP' => '198.51.100.10'
      )

      expect(last_response.status).to eq(403)
      expect(last_response.body).to include('Access denied')
    end
  end
end
