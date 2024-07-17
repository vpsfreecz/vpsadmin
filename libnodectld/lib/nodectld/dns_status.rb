require 'libosctl'
require 'net/http'
require 'rexml/document'
require 'time'

module NodeCtld
  class DnsStatus
    include OsCtl::Lib::Utils::Log

    def initialize
      @mutex = Mutex.new

      @channel = NodeBunny.create_channel
      @exchange = @channel.direct(NodeBunny.exchange_name)
    end

    def start
      @thread = Thread.new do
        loop do
          sleep($CFG.get(:dns_server, :status_interval))
          check_status
        end
      end
    end

    def log_type
      'dns-status'
    end

    protected

    def check_status
      known_zones = DnsConfig.instance.get_zone_names
      return if known_zones.empty?

      now = Time.now
      xml = fetch_bind_stats

      zones = []

      xml.elements.each('//statistics/views/view/zones/zone') do |zone|
        name = "#{zone.attributes['name']}."
        next unless known_zones.include?(name)

        type = zone.elements['type'].text
        serial = zone.elements['serial'].text

        status = {
          time: now.to_i,
          name:,
          type:,
          serial: serial == '-' ? nil : serial.to_i,
          loaded: Time.parse(zone.elements['loaded'].text).to_i
        }

        if type == 'secondary'
          status.update(
            expires: Time.parse(zone.elements['expires'].text).to_i,
            refresh: Time.parse(zone.elements['refresh'].text).to_i
          )
        end

        zones << status
      end

      return if zones.empty?

      NodeBunny.publish_drop(
        @exchange,
        { zones: }.to_json,
        content_type: 'application/json',
        routing_key: 'dns_statuses'
      )
    end

    def fetch_bind_stats
      uri = URI($CFG.get(:dns_server, :statistics_url))
      response = Net::HTTP.get_response(uri)

      if response.code.to_i != 200
        log(:warn, "Failed to fetch BIND stats: HTTP #{response.code} #{response.message}")
        return
      end

      begin
        REXML::Document.new(response.body)
      rescue REXML::ParseException => e
        log(:warn, "Failed to parse XML: #{e.message}")
        nil
      end
    end
  end
end
