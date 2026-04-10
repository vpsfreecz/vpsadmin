# frozen_string_literal: true

require 'fileutils'
require 'json'

RSpec.describe 'VpsAdmin::API::ServiceDiscovery' do
  def deployment_config_path
    File.join(VpsAdmin::API.root, 'config', 'deployment.json')
  end

  def write_deployment_config!(cfg)
    File.write(deployment_config_path, JSON.pretty_generate(cfg))
    VpsAdmin::API::DeploymentConfig.reload!
  end

  def remove_deployment_config!
    FileUtils.rm_f(deployment_config_path)
    VpsAdmin::API::DeploymentConfig.reload!
  end

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
    write_deployment_config!(
      'monitoring' => {
        'download_pool_service_discovery' => {
          'allowed_networks' => allowed_networks,
          'trusted_proxies' => trusted_proxies
        }
      }
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
      remove_deployment_config!
    end

    after do
      remove_deployment_config!
    end

    it 'rejects access when deployment.json is not present' do
      request_download_pool_sd(
        'REMOTE_ADDR' => '198.51.100.10'
      )

      expect(last_response.status).to eq(403)
      expect(last_response.body).to include('Access denied')
    end

    it 'rejects access when allowed networks are not configured' do
      write_deployment_config!(
        'monitoring' => {
          'download_pool_service_discovery' => {
            'trusted_proxies' => ['203.0.113.0/24']
          }
        }
      )

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

    it 'allows direct access from an allowed IPv6 network' do
      configure_download_pool_sd!(allowed_networks: ['2001:db8:1::/64'])

      request_download_pool_sd(
        'REMOTE_ADDR' => '2001:db8:1::10'
      )

      expect(last_response.status).to eq(200)
    end

    it 'allows access through an IPv6 trusted proxy' do
      configure_download_pool_sd!(
        allowed_networks: ['2001:db8:1::/64'],
        trusted_proxies: ['2001:db8:2::/64']
      )

      request_download_pool_sd(
        'REMOTE_ADDR' => '2001:db8:2::20',
        'HTTP_X_REAL_IP' => '2001:db8:1::10'
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

    it 'rejects a direct IPv6 client when only IPv4 networks are allowed' do
      configure_download_pool_sd!(allowed_networks: ['198.51.100.0/24'])

      request_download_pool_sd(
        'REMOTE_ADDR' => '2001:db8::10'
      )

      expect(last_response.status).to eq(403)
      expect(last_response.body).to include('Access denied')
    end

    it 'rejects an IPv6 proxy when trusted proxies are configured only for IPv4' do
      configure_download_pool_sd!(
        allowed_networks: ['198.51.100.0/24'],
        trusted_proxies: ['203.0.113.0/24']
      )

      request_download_pool_sd(
        'REMOTE_ADDR' => '2001:db8::20',
        'HTTP_X_REAL_IP' => '198.51.100.10'
      )

      expect(last_response.status).to eq(403)
      expect(last_response.body).to include('Access denied')
    end

    it 'returns an error on malformed deployment config' do
      File.write(deployment_config_path, '{"monitoring":')
      VpsAdmin::API::DeploymentConfig.reload!

      request_download_pool_sd(
        'REMOTE_ADDR' => '198.51.100.10'
      )

      expect(last_response.status).to eq(500)
      expect(last_response.body).to include('Unable to parse deployment.json')
    end
  end
end
