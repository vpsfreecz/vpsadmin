require 'libosctl'
require 'tempfile'

module NodeCtl
  class Commands::IncidentReport < Command::Local
    cmd :'incident-report'
    description 'Send incident reports to users'

    Incident = Struct.new(
      :vps_id,
      :subject,
      :codename,
      :cpu_limit,
      :admin_id,
      :message,
      keyword_init: true
    )

    class ParseError < ::StandardError; end

    class VpsProcesses
      include OsCtl::Lib::Utils::Humanize

      attr_reader :vps_id

      def initialize(vps_id)
        @vps_id = vps_id
        @os_procs = []
      end

      def <<(os_proc)
        @os_procs << os_proc
      end

      def format
        return @formatted if @formatted

        ret = []

        @os_procs.each do |os_proc|
          ret << format("# %13s: %d\n", 'Host PID', os_proc.pid)
          ret << format("%15s: %d\n", 'PID', os_proc.ct_pid)
          ret << format("%15s: %d\n", 'User ID', os_proc.ct_euid)
          ret << format("%15s: %s\n", 'User name', get_user_name(vps_id, os_proc.ct_euid))
          ret << format("%15s: %s\n", 'Started at', os_proc.start_time.strftime('%Y-%m-%d %H:%M:%S %Z'))
          ret << format("%15s: %s\n", 'Time on CPU', format_short_duration(os_proc.user_time + os_proc.sys_time))
          ret << format("%15s: %s\n", 'Virtual memory', humanize_data(os_proc.vmsize))
          ret << format("%15s: %s\n", 'Used memory', humanize_data(os_proc.rss))
          ret << format("%15s: %s\n", 'Executable', File.readlink(File.join('/proc', os_proc.pid.to_s, 'exe')))
          ret << format("%15s: %s\n", 'Command', os_proc.cmdline)

          tree = []
          tmp = os_proc

          loop do
            ct_pid = tmp.ct_pid
            break if ct_pid.nil?

            tree << tmp
            break if ct_pid == 1

            tmp = tmp.parent
          end

          ret << format("%15s: %s\n", 'Process tree', tree.reverse_each.map do |os_proc|
            "#{os_proc.name}[#{os_proc.ct_pid}]"
          end.join(' - '))

          ret << format('%15s: %s', 'Cgroup', get_cgroup_path(os_proc.pid))

          ret << "\n"
        end

        @formatted = ret
      end

      protected

      def get_user_name(vps_id, uid)
        name = 'not found'

        puts "Looking up name for UID #{uid} in VPS #{vps_id}"

        IO.popen("osctl ct exec #{vps_id} getent passwd #{uid}") do |io|
          out = io.read.strip
          colon = out.index(':')
          next if colon.nil?

          name = out[0..(colon - 1)][0..29]
        end

        name
      end

      def get_cgroup_path(pid)
        cgroups = {}

        File.open(File.join('/proc', pid.to_s, 'cgroup')) do |f|
          f.each_line do |line|
            s = line.strip

            # Hierarchy ID
            colon = s.index(':')
            next if colon.nil?

            s = s[(colon + 1)..-1]

            # Controllers
            colon = s.index(':')
            next if colon.nil?

            subsystems = if colon == 0
                           'unified'
                         else
                           s[0..(colon - 1)].split(',').map do |subsys|
                             # Remove name= from named controllers
                             if eq = subsys.index('=')
                               subsys[(eq + 1)..-1]
                             else
                               subsys
                             end
                           end.join(',')
                         end

            s = s[(colon + 1)..-1]

            # Path
            next if s.nil?

            path = s

            cgroups[subsystems] = path
          end
        end

        path = cgroups['memory'] || cgroups['unified']
        return 'not found' if path.nil?

        lxc_payload = "/lxc.payload.#{vps_id}/"

        i = path.index(lxc_payload)
        return 'not found' if i.nil?

        path[(i + lxc_payload.length - 1)..-1]
      end
    end

    def options(parser, _args)
      parser.separator <<~END
        Subcommands:
        pid pid...        File incident reports based on process IDs
        vps vps...        File incident reports based on VPS IDs
      END
    end

    def validate
      if args.size < 2
        raise ValidationError, 'arguments missing'

      elsif !%w[pid vps].include?(args[0])
        raise ValidationError, "invalid subcommand #{args[0].inspect}"
      end
    end

    def execute
      case args[0]
      when 'pid'
        report_pids

      when 'vps'
        report_vpses

      else
        raise "invalid subcommand #{args[0].inspect}"
      end
    end

    protected

    def report_pids
      vps_procs = {}

      args[1..-1].map(&:to_i).each do |pid|
        os_proc = OsCtl::Lib::OsProcess.new(pid)
        pool, ctid = os_proc.ct_id

        if pool.nil?
          warn "PID #{pid} does not belong to any VPS"
          exit(false)
        end

        vps_id = ctid.to_i

        if vps_id <= 0
          warn "CT #{pool}:#{ctid} is not a vpsAdmin-managed VPS"
          exit(false)
        end

        vps_procs[vps_id] ||= VpsProcesses.new(vps_id)
        vps_procs[vps_id] << os_proc
      end

      if vps_procs.empty?
        warn 'No processes found'
        exit(false)
      end

      incident = open_editor do |f|
        f.puts(<<~END)
          # Lines starting with '#' are comments. Leave an empty line between the header
          # and the message itself. Delete all content to abort.
          #
          Subject:
          # Codename: malware
          # CPU-Limit: 200
          #{admin_headers}

          ### Incident message goes here


        END

        if vps_procs.size == 1
          vps_procs.each_value do |vps_proc|
            f.puts(vps_proc.format.join)
          end
        else
          f.puts('### The following lines are VPS-specific and will be appended automatically:')
          vps_procs.each do |vps_id, vps_proc|
            f.puts("## VPS #{vps_id}")
            f.puts(vps_proc.format.map { |v| "# #{v}" }.join)
          end
        end
      end

      incidents = []

      if vps_procs.size == 1
        incident.vps_id = vps_procs.keys.first
        incidents << incident
      else
        vps_procs.each do |vps_id, vps_proc|
          inc = incident.clone
          inc.vps_id = vps_id
          inc.message = inc.message + "\n\n" + vps_proc.format.reject do |line|
            line.start_with?('#')
          end.join

          incidents << inc
        end
      end

      save_incidents(incidents)
    end

    def report_vpses
      vps_ids = args[1..-1].map(&:to_i)

      incident = open_editor do |f|
        f.puts(<<~END)
          # Lines starting with '#' are comments. Leave an empty line between the header
          # and the message itself. Delete all content to abort.
          #
          Subject:
          # Codename: malware
          # CPU-Limit: 200
          #{admin_headers}

          ### Incident message goes here

        END
      end

      incidents = vps_ids.map do |vps_id|
        inc = incident.clone
        inc.vps_id = vps_id
        inc
      end

      save_incidents(incidents)
    end

    def admin_headers
      admin_id = ENV['VPSADMIN_USER_ID']
      admin_name = ENV['VPSADMIN_USER_NAME']

      if admin_id
        "Admin: #{admin_id} #{admin_name}"
      else
        '# Admin: not found'
      end
    end

    def open_editor
      file = Tempfile.new('nodectl-incident-report')
      yield(file)
      file.close

      loop do
        unless Kernel.system(ENV['EDITOR'], file.path)
          warn "#{ENV['EDITOR']} exited with non-zero status code"
          exit(false)
        end

        if File.empty?(file.path)
          warn 'Aborting on empty file'
          exit(false)
        end

        begin
          incident = parse_file(file.path)
        rescue ParseError => e
          content = File.read(file.path)

          File.open(file.path, 'w') do |f|
            f.puts(<<~END)
              ###
              ### Parse error: #{e.message}
              ###
              #
            END
            f.write(content)
          end
        else
          return incident
        end
      end
    ensure
      file && file.unlink
    end

    def parse_file(path)
      incident = Incident.new(subject: '', codename: nil, cpu_limit: nil, message: '')
      in_header = true

      File.open(path) do |f|
        f.each_line do |line|
          stripped = line.strip
          next if stripped.start_with?('#')

          if in_header
            downcase = stripped.downcase

            if stripped.empty?
              in_header = false
            elsif downcase.start_with?('subject:')
              incident.subject = header_value(stripped)
            elsif downcase.start_with?('codename:')
              incident.codename = header_value(stripped)
            elsif downcase.start_with?('cpu-limit:')
              incident.cpu_limit = header_value(stripped).to_i
            elsif downcase.start_with?('admin:')
              incident.admin_id = header_value(stripped).split.first.to_i
            else
              raise ParseError, "Unknown header in #{line.inspect}"
            end
          else
            incident.message << line
          end
        end
      end

      if incident.subject.empty?
        raise ParseError, 'Missing subject'
      elsif incident.cpu_limit && incident.cpu_limit <= 0
        raise ParseError, 'Invalid CPU limit value'
      elsif incident.admin_id && incident.admin_id <= 0
        raise ParseError, 'Invalid Admin value'
      end

      incident
    end

    def header_value(line)
      colon = line.index(':')
      line[(colon + 1)..-1].strip
    end

    def save_incidents(incidents)
      require 'nodectld/standalone'

      db = NodeCtld::Db.new
      t = Time.now.utc.strftime('%Y-%m-%d %H:%M:%S')

      incidents.each do |inc|
        user_id = db.prepared(
          'SELECT user_id FROM vpses WHERE id = ?',
          inc.vps_id
        ).get!['user_id']

        db.prepared(
          'INSERT INTO incident_reports SET
            user_id = ?,
            vps_id = ?,
            filed_by_id = ?,
            subject = ?,
            text = ?,
            codename = ?,
            cpu_limit = ?,
            detected_at = ?,
            created_at = ?,
            updated_at = ?,
            reported_at = NULL',
          user_id, inc.vps_id, inc.admin_id, inc.subject, inc.message, inc.codename, inc.cpu_limit,
          t, t, t
        )

        puts "Created incident report ##{db.insert_id} for VPS #{inc.vps_id}"

        next unless inc.cpu_limit

        cmd = %W[osctl ct set cpu-limit #{inc.vps_id} #{inc.cpu_limit}]
        puts "  #{cmd.join(' ')}"

        warn "  Failed to set CPU limit on VPS #{inc.vps_id}" unless Kernel.system(*cmd)
      end
    end
  end
end
