require 'shellwords'
require 'open3'

module VpsAdmin::DownloadMounter
  class Mounter
    HEALTHCHECK_FILE = '_vpsadmin-download-healthcheck'.freeze
    HEALTHCHECK_TIMEOUT = 10

    def initialize(opts, mountpoint, pool)
      @opts = opts
      @full_mnt = File.join(
        mountpoint,
        "#{pool.node.domain_name}.#{pool.node.location.environment.domain}",
        pool.id.to_s
      )
      @pool = pool
    end

    def mount
      # FIXME: this assumes that the pool is mounted to /<pool_name>
      src = "#{@pool.node.ip_addr}:/#{@pool.filesystem}/vpsadmin/download"

      if mountpoint_exists?
        puts '  mountpoint found'

      else
        puts '  creating mountpoint'
        unless create_mountpoint
          return remount(
            src,
            'mountpoint creation returned EEXIST, treating it as a stale mount'
          )
        end
      end

      if mounted?
        puts '  is mounted'

        if mounted_healthy?
          true
        else
          remount(src, 'mounted directory failed healthcheck, remounting')
        end

      else
        mount_pool(src)
      end
    end

    def umount
      if mounted?
        run('umount', '-f', @full_mnt)

      else
        puts '  not mounted'
        true
      end
    end

    def mounted?
      Pathname.new(@full_mnt).mountpoint?
    end

    def mountpoint_exists?
      Dir.exist?(@full_mnt)
    end

    protected

    def create_mountpoint
      return true if @opts[:dry_run]

      FileUtils.mkpath(@full_mnt)
      true
    rescue Errno::EEXIST
      false
    end

    def remount(src, reason)
      puts "  #{reason}"

      return false unless run('umount', '-f', @full_mnt, valid_rcs: [0, 32])
      return false unless create_mountpoint

      mount_pool(src)
    end

    def mount_pool(src)
      return false unless run(*mount_command(src))
      return true if @opts[:dry_run]

      mounted_healthy?
    end

    def mount_command(src)
      ['mount', '-t', 'nfs', '-overs=3,nolock', src, @full_mnt]
    end

    def mounted_healthy?
      cmd = ['timeout', HEALTHCHECK_TIMEOUT.to_s, 'cat', healthcheck_path]

      puts "  #{Shellwords.join(cmd)}"
      return true if @opts[:dry_run]

      out, _err, status = Open3.capture3(*cmd)
      actual = out.strip
      expected = @pool.id.to_s

      if status.success? && actual == expected
        true
      else
        report_healthcheck_error(status, actual, expected)
        false
      end
    rescue StandardError => e
      puts "  healthcheck failed: #{e.class}: #{e.message}"
      false
    end

    def healthcheck_path
      File.join(@full_mnt, HEALTHCHECK_FILE)
    end

    def report_healthcheck_error(status, actual, expected)
      if status.exitstatus == 124
        puts "  healthcheck timed out after #{HEALTHCHECK_TIMEOUT} seconds"
      elsif status.success?
        puts "  healthcheck returned #{actual.inspect}, expected #{expected.inspect}"
      else
        puts "  healthcheck exited with status #{status.exitstatus || 'unknown'}"
      end
    end

    def run(*cmd, valid_rcs: [0])
      puts "  #{Shellwords.join(cmd)}"
      return true if @opts[:dry_run]

      system(*cmd)
      status = $?

      if status && valid_rcs.include?(status.exitstatus)
        true
      else
        puts "  command exited with status #{status&.exitstatus || 'unknown'}"
        false
      end
    end
  end
end
