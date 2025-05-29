require 'fileutils'
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

    def initialize(name:, source:, type:, default_ttl: nil, nameservers: nil, serial: nil, email: nil, primaries: nil, secondaries: nil, dnssec_enabled: nil, enabled: nil, load_db: true)
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
      @records = json['records']
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

    def save_zone
      FileUtils.mkdir_p(File.dirname(@db_file))

      regenerate_file(@db_file, 0o644) do |f|
        f.puts(JSON.pretty_generate(dump))
      end
    end

    def dump
      {
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
