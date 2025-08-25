require 'libosctl'
require 'net/http'
require 'rexml/document'
require 'time'

module NodeCtld
  class DnsStatus
    include OsCtl::Lib::Utils::Log

    DnssecKey = Struct.new(:zone_name, :keyid, :file_name, :file_path)

    def initialize
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
      return unless DnsConfig.instance.any_zones?

      now = Time.now
      xml = fetch_bind_stats

      zones = []

      xml.elements.each('//statistics/views/view/zones/zone') do |xml_zone|
        name = "#{xml_zone.attributes['name']}."
        zone = DnsConfig.instance[name]
        next if zone.nil?

        type = xml_zone.elements['type'].text
        serial = xml_zone.elements['serial'].text

        status = {
          time: now.to_i,
          name:,
          type:,
          serial: serial == '-' ? nil : serial.to_i,
          loaded: Time.parse(xml_zone.elements['loaded'].text).to_i,
          dnskeys: []
        }

        if type == 'secondary'
          status.update(
            expires: Time.parse(xml_zone.elements['expires'].text).to_i,
            refresh: Time.parse(xml_zone.elements['refresh'].text).to_i
          )
        end

        if type == 'primary' && zone.dnssec_enabled
          status[:dnskeys] = find_dnskeys(zone)
        end

        zones << status
      end

      @dnskeys = nil
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

    def find_dnskeys(zone)
      @dnskeys ||= list_dnskeys

      zone_keys = @dnskeys.select { |key| key.zone_name == zone.name }
      return [] if zone_keys.empty?

      zone_keys.map do |key|
        dnskey = {
          keyid: key.keyid
        }

        File.open(key.file_path) do |f|
          f.each_line do |line|
            next if line.start_with?(';') || / IN DNSKEY 257 3 (\d+) ([^$]+)/ !~ line

            dnskey.update(
              algorithm: Regexp.last_match(1).to_i,
              pubkey: Regexp.last_match(2).strip
            )

            break
          end
        end

        dnskey[:pubkey] ? dnskey : nil
      end.compact
    end

    def list_dnskeys
      workdir = $CFG.get(:dns_server, :bind_workdir)

      Dir.entries(workdir).map do |v|
        next if /\AK(.+)\+\d+\+(\d+)\.key\z/ !~ v

        DnssecKey.new(
          Regexp.last_match(1),
          Regexp.last_match(2).to_i,
          v,
          File.join(workdir, v)
        )
      end.compact
    end
  end
end
