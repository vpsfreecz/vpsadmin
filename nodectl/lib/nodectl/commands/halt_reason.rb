require 'timeout'

module NodeCtl
  class Commands::HaltReason < Command::Local
    cmd :'halt-reason'
    description 'Look up reported maintenaces/outages for halt reason'

    IMPACT_TYPES = %i[tbd system_restart system_reset network performance unavailability].freeze

    def execute
      # Access db from a subprocess in case it is not accessible
      pid = Process.fork do
        print_reason
      end

      begin
        Timeout.timeout(15) do
          Process.wait(pid)
        end
      rescue Timeout::Error
        warn 'Timed out while fetching outages'
        Process.kill('KILL', pid)
        Process.wait(pid)
      end

      exit($?.exitstatus || 1)
    end

    protected

    def print_reason
      require 'nodectld/standalone'

      db = NodeCtld::Db.new

      # Find self location and environment
      rs = db.prepared(
        'SELECT n.location_id, l.environment_id
        FROM nodes n
        INNER JOIN locations l ON l.id = n.location_id
        WHERE n.id = ?',
        $CFG.get(:vpsadmin, :node_id)
      ).get!

      loc_id = rs['location_id']
      env_id = rs['environment_id']

      # Look up outage reports
      rs = db.prepared(
        "SELECT o.id, o.begins_at, o.duration, o.outage_type, o.impact_type
        FROM outages o
        LEFT JOIN outage_entities e ON e.outage_id = o.id
        WHERE
          o.state = 1
          AND e.name = 'Cluster'
          OR (e.name = 'Environment' AND e.row_id = ?)
          OR (e.name = 'Location' AND e.row_id = ?)
          OR (e.name = 'Node' AND e.row_id = ?)
        GROUP BY o.id
        ORDER BY o.id",
        env_id,
        loc_id,
        $CFG.get(:vpsadmin, :node_id)
      )

      outages = []
      now = Time.now

      rs.each do |outage|
        next unless outage['begins_at'] < now \
           && outage['begins_at'] + (outage['duration'] * 60) >= now

        get_entities(db, outage)
        get_translations(db, outage)
        get_handlers(db, outage)
        outages << outage
      end

      webui = get_webui_url(db)

      # Print message
      if outages.empty?
        puts '# No reported outage was found'
        puts "System is #{get_action_verb}. No outage is reported at this time,"
        puts "it may appear later on #{webui}"

      else
        if outages.length == 1
          puts '# Found one reported outage'
        else
          puts '# Found multiple outages, choose which one is appropriate'
          puts '# and delete the rest'
        end

        outages.each do |outage|
          puts '#'
          puts "# Outage ##{outage['id']}"
          puts "System is #{get_action_verb} due to a reported #{outage['outage_type'] === 0 ? 'maintenance' : 'outage'}:"
          puts "  Reported at: #{fmt_date(outage['begins_at'].localtime)}"
          puts "  Impact type: #{IMPACT_TYPES[outage['impact_type']]}"
          puts "  Duration:    #{outage['duration']} minutes"
          puts "  Reason:      #{outage['summary']}"
          puts "  Handled by:  #{outage['handlers'].join(', ')}"
          puts "  URL:         #{File.join(webui, "?page=outage&action=show&id=#{outage['id']}")}"
        end
      end
    end

    def get_translations(db, outage)
      row = db.prepared(
        'SELECT t.summary, t.description
        FROM outage_translations t
        INNER JOIN languages l ON l.id = t.language_id
        WHERE l.code = ? AND t.outage_id = ? AND outage_update_id IS NULL',
        'en',
        outage['id']
      ).get!

      outage['summary'] = row['summary']
      outage['description'] = row['description']
    end

    def get_entities(db, outage)
      ents = []

      db.prepared(
        'SELECT name, row_id
        FROM outage_entities
        WHERE outage_id = ?',
        outage['id']
      ).each do |row|
        case row['name']
        when 'Cluster'
          ents << 'Cluster-wide'
        when 'Environment'
          label = db.prepared('SELECT label FROM environments WHERE id = ?', row['row_id']).get!['label']
          ents << "Environment #{label}"
        when 'Location'
          label = db.prepared('SELECT label FROM locations WHERE id = ?', row['row_id']).get!['label']
          ents << "Location #{label}"
        when 'Node'
          rs = db.prepared(
            'SELECT n.name, l.domain
            FROM nodes n
            INNER JOIN locations l ON l.id = n.location_id
            WHERE n.id = ?',
            row['row_id']
          ).get!
          ents << "Node #{rs['name']}.#{rs['domain']}"
        else
          ents << rs['name']
        end
      end

      outage['entities'] = ents
    end

    def get_handlers(db, outage)
      handlers = []

      db.prepared(
        'SELECT full_name
        FROM outage_handlers
        WHERE outage_id = ?',
        outage['id']
      ).each do |row|
        handlers << row['full_name']
      end

      outage['handlers'] = handlers
    end

    def get_webui_url(db)
      rs = db.prepared(
        "SELECT `value` FROM sysconfig WHERE category = 'webui' AND name = 'base_url'"
      )
      YAML.safe_load(rs.get!['value'])
    end

    def get_action_verb
      case ENV.fetch('HALT_ACTION')
      when 'halt', 'poweroff'
        'shutting down'
      when 'reboot', 'kexec'
        'rebooting'
      else
        raise "unknown HALT_ACTION #{ENV['HALT_ACTION'].inspect}"
      end
    end

    def fmt_date(time)
      time.strftime('%Y-%m-%d %H:%M %Z')
    end
  end
end
