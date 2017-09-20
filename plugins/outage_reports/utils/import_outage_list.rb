#!/usr/bin/ruby
# Imports outages reported in the outage mailing list to the database.
#
# Usage:
#   1. Go to mailman archive directory, i.e. /var/lib/mailman/archives/public/outage-list
#   2. ./import_outage_list <API URL> <USERNAME> [PASSWORD]
#
require 'base64'
require 'date'
require 'haveapi/client'
require 'highline/import'
require 'json'
require 'nokogiri'

class OutageParser
  HANDLERS = {
      'Pavel Snajdr' => 1,
      'Pavel Snajdr (snajpa)' => 1,
      'Pavel Snajder' => 1,
      'Jakub Skokan' => 51,
      'Jakub Skokan (aither)' => 51,
      'Tomas Srnka' => 4,
      'Tomáš Srnka' => 4,
      'toms' => 4,
      'Richard Marko' => 828,
      'Jiri Medved' => 506,
      'Jiří Medvěd' => 506,
  }

  ENTITIES = {
      'vpsadmin.vpsfree.cz' => ['Node', 5],
      'router1.brq' => ['Location', 4],
      'router2.brq' => ['Location', 4],
      'router1.prg' => ['Location', 3],
      'router2.prg' => ['Location', 3],
  }

  attr_reader :outages

  def initialize(api)
    @outages = []
    @api = api
    load
  end

  def load
    puts "Loading nodes"
    @api.node.list.each do |n|
      ENTITIES[n.domain_name] = ['Node', n.id]
    end
  end

  def parse
    get_files.each do |f|
      outage = {}
      doc = Nokogiri::HTML(File.read(f))
      title = doc.xpath('/html/head/title').text.strip

      if title.start_with?('[vpsFree: outage-list] Neplanovany vypadek')
        outage[:planned] = false

      elsif title.start_with?('[vpsFree: outage-list] Planovany vypadek')
        outage[:planned] = true

      else
        next
      end

      msg = doc.xpath('/html/body/pre').text
      data = extract_data(msg)
      next unless data

      outage[:date] = get_date(data[:date])
      outage[:duration] = data[:duration].to_i
      outage[:entities] = get_entities(data[:servers])
      outage[:handlers] = get_handlers(data[:performed_by])
      outage[:en_summary] = data[:reason_en]
      outage[:cs_summary] = data[:reason_cs]
      outage[:cs_description], outage[:en_description] = get_description(data[:description_cs])
      outage[:type] = get_type(outage)

      if outage[:entities].empty?
        puts "No servers in #{f}"
        next
      end

      @outages << outage
    end
  end

  def import
    @outages.each do |data|
      outage = @api.outage.create({
          planned: data[:planned],
          begins_at: data[:date],
          duration: data[:duration],
          type: data[:type],
          en_summary: data[:en_summary],
          cs_summary: data[:cs_summary],
          en_description: data[:en_description],
          cs_description: data[:cs_description],
      }.delete_if { |k,v| v.nil? })
      puts "Importing outage ##{outage.id}"

      data[:entities].each do |name, id|
        @api.outage.entity.create(
            outage.id,
            {name: name, entity_id: id}.delete_if { |k,v| v.nil? }
        )
      end

      data[:handlers].each do |u|
        @api.outage.handler.create(outage.id, user: u)
      end

      # Do not build a list of affected VPSes. Some VPSes don't exist anymore,
      # some didn't not exist back then, some were migrated to different nodes.
      # `rebuild_affected_vps` can handle only the current configuration, it
      # cannot go backward in time.
      # @api.outage.rebuild_affected_vps(outage.id)

      @api.outage.close(outage.id, send_mail: false)
    end
  end

  protected
  def get_type(outage)
    if outage[:entities].detect { |v| v[0] == 'Location' } \
       && !outage[:entities].detect { |v| v[0] == 'Node' }
      return 'network'
    end

    return 'maintenance' if outage[:entities].detect { |v| v[0] == 'Node' && v[1] == 5 }
    return 'restart' if outage[:planned]
    'reset'
  end

  def get_date(data)
    DateTime.strptime(data, '%Y-%m-%d %H:%M').to_time
  end

  def get_description(data)
    sep = 'ENGLISH:'

    if pos = data.index(sep)
      [data[0..(pos-1)].strip, data[(pos+sep.size)..-1].strip]

    else
      [data, nil]
    end
  end

  def get_handlers(data)
    ret = []

    data.split(',').each do |v|
      name = v.strip

      if HANDLERS.has_key?(name)
        ret << HANDLERS[name]
      else
        puts "Unknown handlers '#{name}'"
      end
    end

    ret
  end

  def get_entities(data)
    ret = []

    return ret unless data

    data.each do |node|
      if ENTITIES.has_key?(node)
        ret << ENTITIES[node]
        ret << [node, nil] if node.start_with?('router')

      else
        ret << [node, nil]
      end
    end

    ret.uniq
  end

  def get_files
    ret = []

    Dir.glob("*/*.html").each do |f|
      name = File.basename(f)
      prefix, suffix = name.split('.')

      next if prefix !~ /^\d+$/
      ret << f
    end

    ret.sort do |a, b|
      File.basename(a) <=> File.basename(b)
    end
  end

  def extract_data(msg)
    from = '-----BEGIN BASE64 ENCODED PARSEABLE JSON-----'
    to = '-----END BASE64 ENCODED PARSEABLE JSON-----'

    start_pos = msg.index(from)
    end_pos = msg.index(to)
    return if start_pos.nil? || end_pos.nil?

    JSON.parse(Base64.decode64(msg[(start_pos+from.size) .. end_pos]), symbolize_names: true)
  end
end

if $0 == __FILE__
  if ARGV.count < 2
    warn "#{$0} <API URL> <USERNAME> [PASSWORD]"
    exit(false)
  end

  password = ARGV[2]
  password ||= ask('Password: ') { |q| q.echo = false }

  api = HaveAPI::Client.new(ARGV[0])
  api.authenticate(:token,
      user: ARGV[1],
      password: password,
      lifetime: 'fixed',
      interval: 900,
  )

  puts "Initializing the parser"
  parser = OutageParser.new(api)

  puts "Parsing messages"
  parser.parse

  puts "Parsed #{parser.outages.count} outage reports"

  if ask('Import? [y/N]') != 'y'
    exit(true)
  end

  puts "Importing outages"
  parser.import
end
