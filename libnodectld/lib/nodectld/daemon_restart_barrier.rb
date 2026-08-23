require 'fileutils'
require 'json'

module NodeCtld
  # A boot-bound marker which keeps nodectld transaction admission closed
  # across process restarts while osctld is being replaced.
  module DaemonRestartBarrier
    PATH = '/run/osctl/nodectld-upgrade-pause.json'.freeze
    # Shared with the vpsAdminOS configuration-switch coordinator.
    LOCK_PATH = "#{PATH}.lock".freeze
    BOOT_ID_PATH = '/proc/sys/kernel/random/boot_id'.freeze
    ORDINARY_RESTART_REASON = 'osctld-restart'.freeze
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
      cfg['reason'] != ORDINARY_RESTART_REASON
    rescue Errno::ENOENT
      false
    rescue JSON::ParserError
      true
    end

    # Claim barrier ownership for an ordinary osctld restart. A same-boot
    # marker owned by a coordinator, an unknown future implementation, or
    # malformed state is preserved and reported as not acquired. Callers may
    # still send the idempotent pause request, but must leave final resume to
    # the marker owner.
    def self.acquire_ordinary(
      path: PATH,
      boot_id_path: BOOT_ID_PATH,
      lock_path: nil
    )
      synchronize(path, lock_path) do
        present, cfg = read_config(path)
        if present
          current_boot = File.read(boot_id_path).strip
          if !valid_boot_marker?(cfg) || cfg['boot_id'] == current_boot
            return ordinary_marker?(cfg, current_boot)
          end
        end

        persist_unlocked(
          reason: ORDINARY_RESTART_REASON,
          path:,
          boot_id_path:
        )
      rescue JSON::ParserError
        false
      end
    end

    # Remove only a marker still owned by the ordinary restart which is being
    # committed. If ownership changed while nodectld was resuming, preserve the
    # new marker so its coordinator remains responsible for the final resume.
    #
    # @return [Symbol] :released, :absent, or :deferred
    def self.release_ordinary(
      path: PATH,
      boot_id_path: BOOT_ID_PATH,
      lock_path: nil
    )
      synchronize(path, lock_path) do
        present, cfg = read_config(path)
        return :absent unless present

        current_boot = File.read(boot_id_path).strip
        if valid_boot_marker?(cfg) && cfg['boot_id'] != current_boot
          return :absent
        end
        return :deferred unless ordinary_marker?(cfg, current_boot)

        File.unlink(path)
        :released
      rescue JSON::ParserError
        :deferred
      end
    end

    def self.read_config(path)
      [true, JSON.parse(File.read(path))]
    rescue Errno::ENOENT
      [false, nil]
    end
    private_class_method :read_config

    def self.valid_boot_marker?(cfg)
      cfg.is_a?(Hash) && cfg['boot_id'].is_a?(String)
    end
    private_class_method :valid_boot_marker?

    def self.ordinary_marker?(cfg, boot_id)
      valid_boot_marker?(cfg) \
        && cfg['boot_id'] == boot_id \
        && cfg['schema'] == 1 \
        && cfg['reason'] == ORDINARY_RESTART_REASON
    end
    private_class_method :ordinary_marker?

    def self.synchronize(path, lock_path)
      lock_path ||= path == PATH ? LOCK_PATH : "#{path}.lock"
      FileUtils.mkdir_p(File.dirname(lock_path))
      File.open(lock_path, File::RDWR | File::CREAT, 0o600) do |lock|
        lock.flock(File::LOCK_EX)
        yield
      end
    end
    private_class_method :synchronize

    def self.persist_unlocked(reason:, path:, boot_id_path:)
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
    private_class_method :persist_unlocked
  end
end
