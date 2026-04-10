module VpsAdmin::API
  class DownloadPoolServiceDiscovery
    HEALTHCHECK_FILE = '_vpsadmin-download-healthcheck'.freeze
    CONFIG_PATH = %w[monitoring download_pool_service_discovery].freeze

    def initialize(request)
      @request = request
    end

    def authenticate
      client_ip = resolved_client_ip
      return false if client_ip.nil?

      allowed_networks.any? do |network|
        network_include_ip?(network, client_ip)
      end
    end

    def render
      ::Pool.joins(:node)
            .includes(node: { location: :environment })
            .where(nodes: { active: true })
            .order(:id)
            .map do |pool|
        {
          targets: [target_url(pool)],
          labels: target_labels(pool)
        }
      end
    end

    protected

    def resolved_client_ip
      return @resolved_client_ip if defined?(@resolved_client_ip)

      @resolved_client_ip = if request_through_trusted_proxy?
                              forwarded_client_ip
                            else
                              peer_ip
                            end
    end

    attr_reader :request

    def request_through_trusted_proxy?
      return false if peer_ip.nil?

      trusted_proxy_networks.any? do |network|
        network_include_ip?(network, peer_ip)
      end
    end

    def peer_ip
      @peer_ip ||= parse_ip(request.env['REMOTE_ADDR'] || request.ip)
    end

    def forwarded_client_ip
      @forwarded_client_ip ||= parse_ip(
        request.env['HTTP_CLIENT_IP'] || request.env['HTTP_X_REAL_IP']
      )
    end

    def allowed_networks
      @allowed_networks ||= load_networks(config_value('allowed_networks'), 'allowed_networks')
    end

    def trusted_proxy_networks
      @trusted_proxy_networks ||= load_networks(config_value('trusted_proxies'), 'trusted_proxies')
    end

    def config
      @config ||= begin
        cfg = VpsAdmin::API::DeploymentConfig.dig(*CONFIG_PATH)

        if cfg.nil?
          {}
        elsif cfg.is_a?(Hash)
          cfg
        else
          raise VpsAdmin::API::Exceptions::ConfigurationError,
                'monitoring.download_pool_service_discovery in deployment.json must be an object'
        end
      end
    end

    def config_value(key)
      config[key]
    end

    def load_networks(networks, key_name)
      return [] if networks.nil?

      unless networks.is_a?(Array)
        raise VpsAdmin::API::Exceptions::ConfigurationError,
              "monitoring.download_pool_service_discovery.#{key_name} in deployment.json must be an array"
      end

      Array(networks).filter_map do |network|
        parse_network(network, key_name)
      end
    end

    def parse_network(network, key_name)
      IPAddress.parse(network.to_s.strip)
    rescue ArgumentError, IPAddress::InvalidAddressError => e
      raise VpsAdmin::API::Exceptions::ConfigurationError,
            "Invalid CIDR in monitoring.download_pool_service_discovery.#{key_name}: " \
            "#{network.inspect} (#{e.message})"
    end

    def parse_ip(ip)
      return nil if ip.nil? || ip.empty?

      IPAddress.parse(ip)
    rescue ArgumentError, IPAddress::InvalidAddressError
      nil
    end

    def network_include_ip?(network, ip)
      return false if ip.nil?
      return false if network.ipv4? != ip.ipv4?

      network.include?(ip)
    end

    def target_url(pool)
      File.join(
        download_base_url,
        pool.node.fqdn,
        pool.id.to_s,
        HEALTHCHECK_FILE
      )
    end

    def target_labels(pool)
      {
        node_id: pool.node.id.to_s,
        node_name: pool.node.domain_name,
        node_fqdn: pool.node.fqdn,
        location_id: pool.node.location_id.to_s,
        location_label: pool.node.location.label,
        pool_id: pool.id.to_s,
        pool_name: pool.name,
        pool_filesystem: pool.filesystem,
        pool_role: pool.role
      }
    end

    def download_base_url
      ::SysConfig.get('core', 'snapshot_download_base_url')
    end
  end
end
