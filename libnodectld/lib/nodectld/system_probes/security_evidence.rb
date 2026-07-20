require 'digest'
require 'json'
require 'time'
require 'zlib'

module NodeCtld::SystemProbes
  class SecurityEvidence
    # Read build metadata from the closure that actually booted. /etc follows
    # the currently activated system and can therefore describe a kernel that
    # has not been booted yet.
    RUN_ROOT = '/run'.freeze
    PROC_ROOT = '/proc'.freeze
    SYS_ROOT = '/sys'.freeze
    VPSADMINOS_CONFIG_ROOT = '/etc/vpsadminos'.freeze
    BOOTED_SYSTEM = File.join(RUN_ROOT, 'booted-system').freeze
    CURRENT_SYSTEM = File.join(RUN_ROOT, 'current-system').freeze
    PROC_SYS_ROOT = File.join(PROC_ROOT, 'sys').freeze
    SYS_MODULE_ROOT = File.join(SYS_ROOT, 'module').freeze
    SYS_LIVEPATCH_ROOT = File.join(SYS_ROOT, 'kernel', 'livepatch').freeze

    BOOTED_METADATA_PATH = File.join(
      BOOTED_SYSTEM,
      'etc', 'vpsadminos', 'security-evidence.json'
    ).freeze
    CURRENT_METADATA_PATH = File.join(
      CURRENT_SYSTEM,
      'etc', 'vpsadminos', 'security-evidence.json'
    ).freeze
    BOOTED_VPSADMIN_METADATA_PATH = File.join(
      BOOTED_SYSTEM,
      'etc', 'vpsadmin', 'build-info.json'
    ).freeze
    CURRENT_VPSADMIN_METADATA_PATH = File.join(
      CURRENT_SYSTEM,
      'etc', 'vpsadmin', 'build-info.json'
    ).freeze
    BOOTED_CONFCTL_INPUTS_PATH = File.join(
      BOOTED_SYSTEM,
      'etc', 'confctl', 'inputs-info.json'
    ).freeze
    CURRENT_CONFCTL_INPUTS_PATH = File.join(
      CURRENT_SYSTEM,
      'etc', 'confctl', 'inputs-info.json'
    ).freeze
    BOOTED_CONFIGURATION_INFO_PATH = File.join(
      BOOTED_SYSTEM,
      'etc', 'confctl', 'configuration-info.json'
    ).freeze
    CURRENT_CONFIGURATION_INFO_PATH = File.join(
      CURRENT_SYSTEM,
      'etc', 'confctl', 'configuration-info.json'
    ).freeze
    LIVEPATCH_MONITOR_PATH = File.join(VPSADMINOS_CONFIG_ROOT, 'livepatch-monitor.json').freeze
    EBPF_MONITOR_PATH = File.join(VPSADMINOS_CONFIG_ROOT, 'ebpf-livepatch-monitor.json').freeze
    EBPF_PIN_ROOT = File.join(
      SYS_ROOT,
      'fs', 'bpf', 'vpsadminos', 'ebpf-livepatch', 'generations'
    ).freeze
    EBPF_STATE_ROOT = File.join(RUN_ROOT, 'ebpf-livepatch').freeze
    BOOT_ID_PATH = File.join(PROC_SYS_ROOT, 'kernel', 'random', 'boot_id').freeze
    BOOT_TIME_PATH = File.join(PROC_ROOT, 'stat').freeze
    BOOTED_MODULES_PATH = File.join(BOOTED_SYSTEM, 'kernel-modules', 'lib', 'modules').freeze
    LIVEPATCH_STATE_ROOT = File.join(RUN_ROOT, 'vpsadminos', 'livepatches').freeze
    MODULES_PATH = File.join(PROC_ROOT, 'modules').freeze
    COMMAND_LINE_PATH = File.join(PROC_ROOT, 'cmdline').freeze
    KERNEL_CONFIG_PATH = File.join(PROC_ROOT, 'config.gz').freeze
    KERNEL_CONFIG_REPORT_INTERVAL = 6 * 60 * 60
    TRACKED_SYSCTLS = %w[
      dev.tty.ldisc_autoload
      fs.protected_fifos
      fs.protected_hardlinks
      fs.protected_regular
      fs.protected_symlinks
      fs.suid_dumpable
      kernel.core_pattern
      kernel.core_pipe_limit
      kernel.dmesg_restrict
      kernel.hung_task_panic
      kernel.hung_task_timeout_secs
      kernel.hung_task_warnings
      kernel.io_uring_disabled
      kernel.io_uring_group
      kernel.kexec_load_disabled
      kernel.kptr_restrict
      kernel.modprobe
      kernel.modules_disabled
      kernel.oops_limit
      kernel.panic
      kernel.panic_on_oops
      kernel.panic_on_warn
      kernel.panic_print
      kernel.perf_event_paranoid
      kernel.randomize_va_space
      kernel.sysctl_unprivileged_bpf_time_adjust_nsec
      kernel.unprivileged_bpf_disabled
      kernel.warn_limit
      kernel.yama.ptrace_scope
      net.core.bpf_jit_harden
      net.netfilter.nf_log_all_netns
      user.max_net_namespaces
      user.max_user_namespaces
      vm.unprivileged_userfaultfd
    ].freeze

    def values(now:, uptime:, reported_release:)
      booted = booted_evidence(now:, uptime:)
      @errors = @booted_errors.map(&:dup)
      current_metadata = read_json(CURRENT_METADATA_PATH)
      current_vpsadmin_metadata = read_json(CURRENT_VPSADMIN_METADATA_PATH, required: false)
      current_confctl_inputs = read_json(CURRENT_CONFCTL_INPUTS_PATH, required: false)
      current_configuration_info = read_configuration_info(
        CURRENT_CONFIGURATION_INFO_PATH,
        'current_configuration_info'
      )
      validate_metadata_schema(current_metadata, 'current_metadata')
      validate_vpsadmin_metadata_schema(current_vpsadmin_metadata, 'current_vpsadmin_metadata')
      kernel = booted.fetch('kernel').merge('reported_release' => reported_release)
      config_text = kernel_config_text(now:)
      kernel['config_text'] = config_text unless config_text.nil?

      {
        'schema_version' => 1,
        'kernel' => kernel,
        'livepatches' => livepatches,
        'ebpf_programs' => ebpf_programs(now:),
        'deployment' => {
          'booted_system' => booted.fetch('booted_system'),
          'current_system' => realpath(CURRENT_SYSTEM)
        },
        'software_versions' => booted.fetch('software_versions') + current_software_versions(
          current_metadata,
          current_vpsadmin_metadata,
          current_confctl_inputs,
          current_configuration_info
        ),
        'loaded_modules' => loaded_modules,
        'sysctls' => sysctls(current_metadata.fetch('sysctls', nil)),
        'errors' => @errors
      }
    end

    # Kernel configuration content is sent periodically and whenever its
    # digest changes. Do not advance the schedule until the containing status
    # message has actually been accepted by Bunny.
    def report_published
      return unless @pending_config_report

      @last_config_digest = @pending_config_report.fetch(:digest)
      @last_config_reported_at = @pending_config_report.fetch(:reported_at)
      @pending_config_report = nil
    end

    protected

    def booted_evidence(now:, uptime:)
      return @booted_evidence if @booted_evidence

      @errors = []
      metadata = read_json(BOOTED_METADATA_PATH)
      vpsadmin_metadata = read_json(BOOTED_VPSADMIN_METADATA_PATH, required: false)
      confctl_inputs = read_json(BOOTED_CONFCTL_INPUTS_PATH, required: false)
      configuration_info = read_configuration_info(
        BOOTED_CONFIGURATION_INFO_PATH,
        'booted_configuration_info'
      )
      validate_metadata_schema(metadata, 'booted_metadata')
      validate_vpsadmin_metadata_schema(vpsadmin_metadata, 'booted_vpsadmin_metadata')
      command_line = read_value(COMMAND_LINE_PATH)
      config = kernel_config(metadata['kernelConfig'])
      @kernel_config_content = config.delete('config_text')
      @booted_evidence = {
        'kernel' => {
          'boot_id' => read_value(BOOT_ID_PATH),
          'booted_at' => booted_at(now, uptime),
          'booted_release' => booted_release || metadata['kernelModDirVersion'],
          'kernel_source_revision' => metadata['kernelSourceRevision'],
          'booted_params' => parse_command_line(command_line),
          'command_line' => command_line,
          **config
        },
        'booted_system' => realpath(BOOTED_SYSTEM),
        'software_versions' => booted_software_versions(
          metadata,
          vpsadmin_metadata,
          confctl_inputs,
          configuration_info
        )
      }
      @booted_errors = @errors.map(&:dup).freeze
      @booted_evidence
    end

    def validate_metadata_schema(metadata, component)
      return if metadata['schemaVersion'] == 1

      record_error(component, 'supported metadata is unavailable')
    end

    def validate_vpsadmin_metadata_schema(metadata, component)
      return if metadata.empty?
      return if metadata['schemaVersion'] == 1

      record_error(component, 'schema version 1 metadata is unavailable')
    end

    def booted_software_versions(
      metadata,
      vpsadmin_metadata,
      confctl_inputs,
      configuration_info = nil
    )
      [
        software_version('booted', 'vpsadminos', metadata, confctl_inputs),
        software_version('booted', 'vpsadmin', vpsadmin_metadata, confctl_inputs),
        software_version(
          'booted',
          'nixpkgs',
          metadata,
          confctl_inputs,
          version_key: 'nixpkgsVersion',
          revision_key: 'nixpkgsRevision',
          dirty_key: nil
        ),
        system_configuration_software_version('booted', configuration_info)
      ].compact
    end

    def current_software_versions(
      metadata,
      vpsadmin_metadata,
      confctl_inputs,
      configuration_info = nil
    )
      versions = [
        software_version('current', 'vpsadminos', metadata, confctl_inputs),
        software_version('current', 'vpsadmin', vpsadmin_metadata, confctl_inputs),
        software_version(
          'current',
          'nixpkgs',
          metadata,
          confctl_inputs,
          version_key: 'nixpkgsVersion',
          revision_key: 'nixpkgsRevision',
          dirty_key: nil
        ),
        system_configuration_software_version('current', configuration_info)
      ].compact
      verify_running_vpsadmin(vpsadmin_metadata, versions)
      versions
    end

    def system_configuration_software_version(generation, metadata)
      return if metadata.nil?

      {
        'generation' => generation,
        'component' => 'system_configuration',
        'version' => nil,
        'version_source' => nil,
        'revision' => metadata.fetch('revision'),
        'revision_source' => 'native',
        'revision_dirty' => metadata.fetch('revisionDirty')
      }
    end

    def software_version(
      generation,
      component,
      metadata,
      confctl_inputs,
      version_key: 'version',
      revision_key: 'revision',
      dirty_key: 'revisionDirty'
    )
      version = nonempty_string(metadata[version_key])
      version_source = version.nil? ? nil : 'native'
      revision = exact_revision(metadata[revision_key])
      revision_source = revision.nil? ? nil : 'native'
      revision_dirty = false

      if !revision.nil? && !dirty_key.nil?
        dirty_value = metadata[dirty_key]
        if [true, false].include?(dirty_value)
          revision_dirty = dirty_value
        else
          revision = nil
          revision_source = nil
        end
      end

      if revision.nil?
        confctl_input = confctl_inputs[component]
        revision = exact_revision(confctl_input['rev']) if confctl_input.is_a?(Hash)
        unless revision.nil?
          revision_source = 'confctl'
          revision_dirty = false
        end
      end

      if revision.nil?
        record_error("software.#{generation}.#{component}.revision", 'missing')
      end

      {
        'generation' => generation,
        'component' => component,
        'version' => version,
        'version_source' => version_source,
        'revision' => revision,
        'revision_source' => revision_source,
        'revision_dirty' => revision_dirty
      }
    end

    def verify_running_vpsadmin(current_metadata, versions)
      running_revision = exact_revision(ENV.fetch('VPSADMIN_REVISION', nil))
      record_error('running_vpsadmin.revision', 'missing') if running_revision.nil?
      current = versions.find do |version|
        version['generation'] == 'current' && version['component'] == 'vpsadmin'
      end

      if running_revision && current['revision'] && running_revision != current['revision']
        record_error('running_vpsadmin.revision', 'does not match current system closure')
      end
      return if current_metadata['version'].nil? || current_metadata['version'] == NodeCtld::VERSION

      record_error('running_vpsadmin.version', 'does not match current system closure')
    end

    def nonempty_string(value)
      value if value.is_a?(String) && !value.empty?
    end

    def exact_revision(value)
      value if value.is_a?(String) && value.match?(/\A[0-9a-f]{40}\z/)
    end

    def realpath(path)
      File.realpath(path)
    rescue SystemCallError
      record_error(path_key(path), 'unavailable')
      nil
    end

    def booted_at(now, uptime)
      line = File.read(BOOT_TIME_PATH).each_line.find { |candidate| candidate.start_with?('btime ') }
      raise 'btime is missing' unless line

      Time.at(Integer(line.split.fetch(1))).utc.iso8601
    rescue ArgumentError, RuntimeError, SystemCallError
      record_error('booted_at', 'estimated_from_uptime')
      (now - uptime).utc.iso8601
    end

    def booted_release
      entries = Dir.children(BOOTED_MODULES_PATH).reject { |entry| entry.start_with?('.') }.sort
      return entries.first if entries.length == 1

      record_error('booted_release', entries.empty? ? 'missing' : 'ambiguous')
      nil
    rescue SystemCallError
      record_error('booted_release', 'unavailable')
      nil
    end

    def parse_command_line(command_line)
      return [] if command_line.nil?

      ret = []
      token = +''
      quoted = false
      started = false
      command_line.each_char do |char|
        if char == '"'
          quoted = !quoted
          started = true
        elsif char.match?(/\s/) && !quoted
          if started
            ret << token
            token = +''
            started = false
          end
        else
          token << char
          started = true
        end
      end
      raise ArgumentError, 'unterminated quote' if quoted

      ret << token if started
      ret
    rescue ArgumentError
      record_error('kernel.command_line', 'invalid')
      []
    end

    def livepatches
      monitor = read_json(LIVEPATCH_MONITOR_PATH, required: false)
      return [] if monitor.empty?

      module_name = monitor['module']
      sysfs_path = File.join(SYS_LIVEPATCH_ROOT, module_name)

      [{
        'id' => module_name,
        'kernel_version' => monitor['kernelVersion'],
        'patch_version' => monitor['patchVersion'],
        'patches' => monitor.fetch('patches', []),
        'loaded' => Dir.exist?(File.join(SYS_MODULE_ROOT, module_name)),
        'enabled' => read_value(File.join(sysfs_path, 'enabled'), required: false) == '1',
        'transition' => read_value(File.join(sysfs_path, 'transition'), required: false) == '1',
        'applied_at' => read_value(
          File.join(LIVEPATCH_STATE_ROOT, "#{module_name}.applied-at"),
          required: false
        )
      }]
    end

    def ebpf_programs(now:)
      monitor = read_json(EBPF_MONITOR_PATH, required: false)
      programs = monitor.fetch('programs', [])
      states = programs.map do |program|
        link_fields = program.fetch('linkFields') { program.fetch('bpfPrograms', []) }
        pins = link_fields.to_h do |link|
          pattern = File.join(EBPF_PIN_ROOT, '*', "#{program.fetch('name')}__#{link}")
          [link, !Dir.glob(pattern).empty?]
        end
        active = !pins.empty? && pins.values.all?

        program.merge(
          'links' => pins,
          'active' => active
        )
      end
      attached_at = ebpf_attached_at if states.any? { |program| program['active'] }

      states.map do |program|
        program.merge(
          'attached_at' => program['active'] ? attached_at : nil,
          'verified_at' => program['active'] ? now.utc.iso8601 : nil
        )
      end
    end

    def ebpf_attached_at
      generation = File.read(File.join(EBPF_STATE_ROOT, 'current-generation')).strip
      raise 'invalid generation' unless generation.match?(/\A\d+-\d+\z/)

      value = File.read(File.join(EBPF_STATE_ROOT, "#{generation}.attached-at")).strip
      Time.iso8601(value).utc.iso8601
    rescue ArgumentError, RuntimeError, SystemCallError
      record_error('ebpf_attached_at', 'unavailable')
      nil
    end

    def loaded_modules
      File.readlines(MODULES_PATH, chomp: true).filter_map do |line|
        name = line.split.first
        name unless name.nil? || name.empty?
      end.sort
    rescue SystemCallError
      record_error('loaded_modules', 'unavailable')
      []
    end

    def sysctls(declared)
      unless declared.is_a?(Hash)
        record_error('declared_sysctls', 'missing')
        declared = {}
      end

      TRACKED_SYSCTLS.to_h do |name|
        path = File.join(PROC_SYS_ROOT, name.tr('.', '/'))
        [
          name,
          read_sysctl(path, name).merge(
            'configured' => canonical_sysctl_value(declared[name])
          )
        ]
      end
    end

    def canonical_sysctl_value(value)
      case value
      when nil
        nil
      when true
        '1'
      when false
        '0'
      else
        value.to_s
      end
    end

    def read_sysctl(path, name)
      {
        'available' => true,
        'effective' => File.read(path).strip
      }
    rescue Errno::ENOENT
      {
        'available' => false,
        'effective' => nil
      }
    rescue SystemCallError
      record_error("sysctl.#{name}", 'unavailable')
      {
        'available' => true,
        'effective' => nil
      }
    end

    def kernel_config(path)
      content = kernel_config_content(path)
      {
        'config_digest' => Digest::SHA256.hexdigest(content),
        'config_text' => content
      }
    rescue SystemCallError, TypeError, Zlib::GzipFile::Error
      record_error('kernel_config', 'unavailable')
      { 'config_digest' => nil }
    end

    def kernel_config_text(now:)
      digest = @booted_evidence.dig('kernel', 'config_digest')
      return if digest.nil? || @kernel_config_content.nil?
      return unless config_report_due?(digest, now)

      @pending_config_report = { digest:, reported_at: now }
      @kernel_config_content
    end

    def kernel_config_content(path)
      return File.read(path) unless path.nil?

      Zlib::GzipReader.open(KERNEL_CONFIG_PATH, &:read)
    rescue SystemCallError
      Zlib::GzipReader.open(KERNEL_CONFIG_PATH, &:read)
    end

    def config_report_due?(digest, now)
      @last_config_digest != digest ||
        @last_config_reported_at.nil? ||
        now - @last_config_reported_at >= KERNEL_CONFIG_REPORT_INTERVAL
    end

    def read_json(path, required: true)
      value = JSON.parse(File.read(path))
      return value if value.is_a?(Hash)

      record_error(path_key(path), 'invalid')
      {}
    rescue Errno::ENOENT
      record_error(path_key(path), 'missing') if required
      {}
    rescue JSON::ParserError, SystemCallError
      record_error(path_key(path), 'invalid')
      {}
    end

    def read_configuration_info(path, component)
      value = JSON.parse(File.read(path))
      unless value.is_a?(Hash) &&
             value['schemaVersion'] == 1 &&
             exact_revision(value['revision']) &&
             [true, false].include?(value['revisionDirty'])
        record_error(component, 'invalid')
        return
      end

      value
    rescue Errno::ENOENT
      nil
    rescue JSON::ParserError, SystemCallError
      record_error(component, 'invalid')
      nil
    end

    def read_value(path, required: true, component: nil)
      File.read(path).strip
    rescue SystemCallError
      record_error(component || path_key(path), 'unavailable') if required
      nil
    end

    def path_key(path)
      File.basename(path).sub(/\.json\z/, '').tr('-', '_')
    end

    def record_error(component, reason)
      @errors << { 'component' => component, 'reason' => reason }
    end
  end
end
