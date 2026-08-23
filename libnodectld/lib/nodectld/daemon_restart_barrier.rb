require 'fileutils'
require 'json'

module NodeCtld
  # A boot-bound marker which keeps nodectld transaction admission closed
  # across process restarts while osctld is being replaced.
  module DaemonRestartBarrier
    PATH = '/run/osctl/nodectld-upgrade-pause.json'.freeze
    BOOT_ID_PATH = '/proc/sys/kernel/random/boot_id'.freeze
    LEGACY_UPGRADE_REASON = 'legacy-osctld-runtime-upgrade'.freeze

    def self.active?(path: PATH, boot_id_path: BOOT_ID_PATH)
      cfg = JSON.parse(File.read(path))
      return true unless cfg.is_a?(Hash) && cfg['boot_id'].is_a?(String)
      return false unless cfg['boot_id'] == File.read(boot_id_path).strip
      return true unless cfg['schema'] == 1

      true
    rescue Errno::ENOENT
      false
    rescue JSON::ParserError
      true
    end

    # A legacy-to-new switch owns the final resume because only its
    # coordinator can prove that target osctld has reached readiness. Invalid
    # marker state also defers forever so it cannot be cleared fail-open.
    def self.coordinator_resume?(path: PATH, boot_id_path: BOOT_ID_PATH)
      cfg = JSON.parse(File.read(path))
      return true unless cfg.is_a?(Hash) && cfg['boot_id'].is_a?(String)
      return false unless cfg['boot_id'] == File.read(boot_id_path).strip
      return true unless cfg['schema'] == 1

      # Only the marker written by the ordinary osctld pre-stop hook is safe
      # for this hook to clear. Unknown same-boot reasons remain paused for a
      # coordinator or operator that understands them.
      cfg['reason'] != 'osctld-restart'
    rescue Errno::ENOENT
      false
    rescue JSON::ParserError
      true
    end

    def self.persist(
      reason:,
      path: PATH,
      boot_id_path: BOOT_ID_PATH
    )
      cfg = {
        'schema' => 1,
        'boot_id' => File.read(boot_id_path).strip,
        'created_at' => Time.now.to_f,
        'reason' => reason
      }
      FileUtils.mkdir_p(File.dirname(path))
      tmp = "#{path}.#{$$}.new"
      File.write(tmp, JSON.pretty_generate(cfg))
      File.chmod(0o600, tmp)
      File.rename(tmp, path)
      true
    ensure
      File.unlink(tmp) if tmp && File.exist?(tmp)
    end

    def self.clear(path: PATH)
      FileUtils.rm_f(path)
    end
  end
end
