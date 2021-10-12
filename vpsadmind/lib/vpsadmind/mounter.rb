require 'pathname'

module VpsAdmind
  # Mounter takes care of mounting and umounting local/remote
  # datasets/snapshots to VPS.
  class Mounter
    include Utils::Log
    include Utils::System
    include Utils::Vps
    include Utils::Pool

    class << self
      def mount_all(vps_id, mounts, oneshot, mode: nil)
        mounter = new(vps_id)
        mounts.each { |mnt| mounter.mount(mnt, oneshot) }
      end

      def umount_all(vps_id, mounts, mode: nil)
        mounter = new(vps_id)
        mounts.each { |mnt| mounter.umount(mnt, keep_going: mode == :actionscript) }
      end
    end

    def initialize(vps_id)
      @vps_id = vps_id
      @failed_mounts = {}
    end

    def mount_cmd(mnt)
      dst = sanitize_dst(ve_root, mnt['dst'])
      src_check = mount_src_check(mnt)

      cmd = case mnt['type']
        when 'dataset_local'
          "#{$CFG.get(:bin, :mount)} #{mnt['mount_opts']} -o#{mnt['mode']} /#{mnt['pool_fs']}/#{mnt['dataset_name']}/private #{dst}"

        when 'dataset_remote'
          "#{$CFG.get(:bin, :mount)} #{mnt['mount_opts']} -o#{mnt['mode']} #{src_check} #{dst}"

        when 'snapshot_local'
          "#{$CFG.get(:bin, :mount)} --bind /#{pool_mounted_snapshot(mnt['pool_fs'], mnt['clone_name'])}/private #{dst}"

        when 'snapshot_remote'
          "#{$CFG.get(:bin, :mount)} #{mnt['mount_opts']} -o#{mnt['mode']} #{src_check} #{dst}"

        else
          fail "unknown mount type '#{mnt['type']}'"
      end

      [src_check, dst, cmd]
    end

    def mount_src_check(mnt)
      case mnt['type']
      when 'dataset_local'
        File.join(mnt['pool_fs'], mnt['dataset_name'])

      when 'dataset_remote'
        "#{mnt['src_node_addr']}:/#{mnt['pool_fs']}/#{mnt['dataset_name']}/private/"

      when 'snapshot_local'
        pool_mounted_snapshot(mnt['pool_fs'], mnt['clone_name'])

      when 'snapshot_remote'
        "#{mnt['src_node_addr']}:/#{pool_mounted_snapshot(mnt['pool_fs'], mnt['clone_name'])}/private"

      else
        fail "unknown mount type '#{mnt['type']}'"
      end
    end

    def mount(opts, oneshot)
      counter = 0
      mounted = false
      src_check, dst, cmd = mount_cmd(opts)

      unless oneshot
        # Check if a parent mount did not fail
        @failed_mounts.each do |m_dst, m_level|
          if dst.start_with?(m_dst)
            case m_level
              when 'skip'
                fail_mount(opts)

              when 'mount_later'
                mount_later(opts)
                fail_mount(opts)

              else
                # nothing to do, as it cannot be fail_start nor wait_for_mount
            end

            return
          end
        end
      end

      create_dst(dst)

      begin
        syscmd(cmd)
        mounted = true

      rescue CommandFailed => e
        if /is busy or already mounted/ =~ e.output
          log(:info, :mounter, 'Already mounted')

        else
          raise e if oneshot

          case opts['on_start_fail']
            when 'skip'
              fail_mount(opts)
              report_state(opts, :skipped)
              return

            when 'mount_later'
              # state is set by mount_later
              mount_later(opts)
              fail_mount(opts)

            when 'fail_start'
              report_state(opts, :unmounted)
              raise e

            when 'wait_for_mount'
              report_state(opts, :waiting) if counter == 0
              counter += 1
              wait = random_wait(counter)

              log(:warn, :mounter, "Mount failed, retrying in #{wait} seconds")
              sleep(wait)
              retry

            else
              fail "unsupported value of mount on_start_fail '#{mnt['on_start_fail']}'"
          end
        end
      end

      check_mounttable(opts, src_check)
      report_state(opts, :mounted) if mounted
    end

    def umount_cmd(mnt)
      dst = sanitize_dst(ve_root, mnt['dst'])
      [dst, "#{$CFG.get(:bin, :umount)} #{mnt['umount_opts']} #{dst}"]
    end

    def umount(opts, keep_going: false)
      dst, cmd = umount_cmd(opts)

      if File.exists?(dst)
        begin
          syscmd(cmd)

        rescue CommandFailed => e
          raise e if !keep_going && (e.rc != 1 || /not mounted/ !~ e.output)
        end
      end

      report_state(opts, :unmounted)
    end

    protected
    def create_dst(dst)
      return if File.exists?(dst)
      FileUtils.mkpath(dst)

    rescue Errno::EEXIST
      # it means, that the folder is mounted but was removed on the other end
      syscmd("#{$CFG.get(:bin, :umount)} -f #{dst}")
    end

    def sanitize_dst(root, dst)
      path = File.join(root, dst)
      tmp = []

      Pathname.new(dst).each_filename do |fn|
        tmp << fn
        abs_path = File.join(root, *tmp)

        if File.symlink?(abs_path)
          fail "VPS #{@vps_id}: refusing to touch '#{dst}': '#{abs_path}' is a symlink"
        end
      end

      path
    end

    def check_mounttable(mnt, src_check)
      found = false

      File.open('/proc/mounts').each_line do |line|
        next unless line.start_with?(src_check)

        cols = line.split(' ')

        if cols[0] == src_check
          found = true

          if cols[1].start_with?(ve_root)
            log(:info, :mounter, "VPS #{@vps_id}: allowing mount '#{cols[1]}'")
          elsif cols[1].start_with?(ve_private) # subdatasets mounted in /vz/private
            # pass
          elsif mnt['type'] == 'snapshot_local' \
                && cols[1].start_with?("/#{pool_mounted_snapshot(mnt['pool_fs'], mnt['clone_name'])}")
            # pass
          elsif /^\/vz\/root\/(\d+)\// =~ cols[1] \
                && check_vps_mounts_for($1, src_check)
            # pass, mount of the same src to another VPS
          else
            log(:fatal, :mounter, "VPS #{@vps_id}: forbidden mount found at '#{cols[1]}'")
            syscmd("#{$CFG.get(:bin, :umount)} -fl \"#{cols[1]}\"")
            fail "VPS #{@vps_id}: forbidden mount found at '#{cols[1]}'"
          end
        end
      end

      unless found
        log(:warn, :mounter, "VPS #{@vps_id}: did not find mount of '#{src_check}'")
      end
    end

    def check_vps_mounts_for(vps_id, src_check)
      mounts_file = File.join($CFG.get(:vpsadmin, :mounts_dir), "#{vps_id}.mounts")
      return false unless File.exist?(mounts_file)

      if ::Object.const_defined?(:MOUNTS)
        ::Object.send(:remove_const, :MOUNTS)
      end

      begin
        load mounts_file
      rescue LoadError
        return false
      end

      return false unless ::Object.const_defined?(:MOUNTS)

      found = MOUNTS.detect do |m|
        mount_src_check(m) == src_check
      end

      ::Object.send(:remove_const, :MOUNTS)

      found ? true : false
    end

    def fail_mount(opts)
      @failed_mounts[File.join(opts['dst'], '/')] = opts['on_start_fail']
    end

    def mount_later(opts)
      log(:info, :mounter, 'Delaying mount')

      if VpsAdmind::STANDALONE
        RemoteClient.send_or_not($CFG.get(:remote, :socket), :delayed_mount, {
            :vps_id => @vps_id,
            :mount => opts
        })

      else
        DelayedMounter.mount(@vps_id, opts)
      end
    end

    def report_state(opts, state)
      if VpsAdmind::STANDALONE
        RemoteClient.send_or_not($CFG.get(:remote, :socket), :mount_state, {
            :vps_id => @vps_id,
            :mount_id => opts['id'],
            :state => state
        })

      else
        MountReporter.report(@vps_id, opts['id'], state)
      end
    end

    def random_wait(counter)
      base = 10 + counter * 5
      base = 60 if base > 60

      r = 10 + counter * 10
      r = 240 if r > 240

      base + rand(r)
    end
  end
end
