module VpsAdmin::API
  class DownloadPoolServiceDiscovery
    HEALTHCHECK_FILE = '_vpsadmin-download-healthcheck'.freeze

    def initialize(request)
      @request = request
    end

    def authenticate
      client_ip = resolved_client_ip
      return false if client_ip.nil?

      allowed_networks.any? do |network|
        network.include?(client_ip)
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
        network.include?(peer_ip)
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
      @allowed_networks ||= load_networks(
        ::SysConfig.get('monitoring', 'download_pool_sd_allowed_networks')
      )
    end

    def trusted_proxy_networks
      @trusted_proxy_networks ||= load_networks(
        ::SysConfig.get('monitoring', 'download_pool_sd_trusted_proxies')
      )
    end

    def load_networks(networks)
      Array(networks).filter_map do |network|
        parse_network(network)
      end
    end

    def parse_network(network)
      IPAddress.parse(network.to_s.strip)
    rescue ArgumentError, IPAddress::InvalidAddressError => e
      warn "Ignoring invalid CIDR in download pool service discovery config: #{network.inspect} (#{e.message})"
      nil
    end

    def parse_ip(ip)
      return nil if ip.nil? || ip.empty?

      IPAddress.parse(ip)
    rescue ArgumentError, IPAddress::InvalidAddressError
      nil
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
