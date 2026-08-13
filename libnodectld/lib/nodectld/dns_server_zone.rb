require 'fileutils'
require 'ipaddress'
require 'libosctl'

module NodeCtld
  class DnsServerZone
    include OsCtl::Lib::Utils::File

    # @return [String]
    attr_reader :name

    # @return [String]
    attr_reader :source

    # @return [String]
    attr_reader :type

    # @return [String]
    attr_reader :zone_file

    # @return [Array(String)]
    attr_reader :nameservers

    # @return [Array(Hash)]
    attr_reader :primaries

    # @return [Array(Hash)]
    attr_reader :secondaries

    # @return [Boolean]
    attr_reader :dnssec_enabled

    # @return [Boolean]
    attr_reader :enabled

    # @return [Integer]
    attr_reader :id

    # @return [String]
    attr_reader :primary_transfer_generation

    # @return [Integer]
    attr_reader :primary_transfer_tracking_started_at

    # @return [Hash]
    attr_reader :probe_source_addrs

    # @return [Integer, nil]
    attr_accessor :loaded_serial

    def initialize(name:, source:, type:, id: nil, default_ttl: nil, nameservers: nil, serial: nil, email: nil, primaries: nil, secondaries: nil, dnssec_enabled: nil, enabled: nil, primary_transfer_generation: nil, primary_transfer_tracking_started_at: nil, probe_source_addrs: nil, load_db: true)
      @id = id
      @name = name
      @source = source
      @type = type
      @default_ttl = default_ttl
      @nameservers = nameservers
      @serial = serial
      @email = email
      @primaries = primaries
      @secondaries = secondaries
      @dnssec_enabled = dnssec_enabled
      @enabled = enabled
      @primary_transfer_generation = primary_transfer_generation
      @primary_transfer_tracking_started_at = primary_transfer_tracking_started_at
      @probe_source_addrs = probe_source_addrs
      @db_file = format($CFG.get(:dns_server, :db_template), name:, source:, type:)
      @zone_file = format($CFG.get(:dns_server, :zone_template), name:, source:, type:)
      self.load_db if load_db
    end

    def load_db
      begin
        json = JSON.parse(File.read(@db_file))
      rescue Errno::ENOENT
        return
      end

      @source ||= json['source']
      @type ||= json['type']
      @default_ttl ||= json['default_ttl']
      @nameservers ||= json['nameservers']
      @serial ||= json['serial']
      @email ||= json['email']
      @primaries ||= json['primaries']
      @secondaries ||= json['secondaries']
      @dnssec_enabled = json['dnssec_enabled'] if @dnssec_enabled.nil?
      @enabled = json['enabled'] if @enabled.nil?
      @id ||= json['id']
      @primary_transfer_generation ||= json['primary_transfer_generation']
      @primary_transfer_tracking_started_at ||= json['primary_transfer_tracking_started_at']
      @probe_source_addrs ||= json['probe_source_addrs']
      @records = json['records']
    end

    def user_primaries
      Array(@primaries).select { |primary| primary['kind'] == 'user_primary' }
    end

    def user_primary_by_addr(addr)
      normalized = normalize_ip_address(addr)
      user_primaries.find do |primary|
        normalize_ip_address(primary['ip_addr']) == normalized
      end
    end

    def probe_source_addr(primary_addr)
      family = primary_addr.to_s.include?(':') ? 'ipv6' : 'ipv4'
      @probe_source_addrs && @probe_source_addrs[family]
    end

    def replace_all_records(records)
      @records = records
      save
    end

    def update_record(record)
      r = @records.detect { |v| v['id'] == record['id'] }

      if r
        r.update(record)
      else
        @records << record
      end

      save
      nil
    end

    alias create_record update_record

    def delete_record(record)
      @records.delete_if do |v|
        v['id'] == record['id']
      end

      save
      nil
    end

    def save
      save_zone
      generate_zone
    end

    def destroy
      unlink_if_exists(@zone_file)
      unlink_if_exists(@db_file)
    end

    protected

    def normalize_ip_address(addr)
      IPAddress.parse(addr).to_s
    rescue ArgumentError, IPAddress::InvalidAddressError
      nil
    end

    def save_zone
      FileUtils.mkdir_p(File.dirname(@db_file))

      regenerate_file(@db_file, 0o644) do |f|
        f.puts(JSON.pretty_generate(dump))
      end
    end

    def dump
      {
        id: @id,
        name: @name,
        source: @source,
        type: @type,
        default_ttl: @default_ttl,
        nameservers: @nameservers,
        serial: @serial,
        email: @email,
        primaries: @primaries,
        secondaries: @secondaries,
        dnssec_enabled: @dnssec_enabled,
        enabled: @enabled,
        primary_transfer_generation: @primary_transfer_generation,
        primary_transfer_tracking_started_at: @primary_transfer_tracking_started_at,
        probe_source_addrs: @probe_source_addrs,
        records: @records
      }
    end

    def generate_zone
      FileUtils.mkdir_p(File.dirname(@zone_file))
      FileUtils.chown('named', 'named', File.dirname(@zone_file))

      return if @source == 'external_source' || @type == 'secondary_type'

      regenerate_file(@zone_file, 0o644) do |f|
        f.puts("$ORIGIN #{@name}")
        f.puts("$TTL #{@default_ttl}")
        f.puts("@ IN SOA #{@nameservers.first}. #{format_email} #{@serial} 1D 2H 4W 1H")

        @nameservers.each do |ns|
          f.puts("@ IN  NS #{ns.end_with?('.') ? ns : "#{ns}."}")
        end

        sort_records.each do |r|
          line = format(
            '%-25s %4s  IN  %-8s %2s %s',
            r['name'],
            r['ttl'] ? r['ttl'].to_s : '',
            r['type'],
            r['priority'] ? r['priority'].to_s : '',
            format_content(r)
          )
          f.puts(line)
        end
      end
    end

    def format_email
      user, domain = @email.split('@')
      "#{user.gsub('.', '\.')}.#{domain}."
    end

    def format_content(r)
      case r['type']
      when 'TXT'
        "(#{r['content'].scan(/.{1,255}/).map { |s| "\"#{escape_txt_content(s)}\"" }.join(' ')})"
      else
        r['content']
      end
    end

    def escape_txt_content(content)
      content.gsub('\\', '\\\\').gsub('"', '\"').gsub("\r", '\r').gsub("\n", '\n')
    end

    def sort_records
      all_integers = @records.all? { |r| /\A\d+\z/ =~ r['name'] }

      @records.sort do |a, b|
        sort_key(a, all_integers) <=> sort_key(b, all_integers)
      end
    end

    def sort_key(r, all_integers)
      [
        r['type'],
        all_integers ? r['name'].to_i : r['name'],
        r['priority'] || 0,
        r['ttl'] || @default_ttl
      ]
    end
  end
end
