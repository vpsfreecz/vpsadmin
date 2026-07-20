require 'digest'
require 'time'

module VpsAdmin::API::KernelEvidence
  class PayloadParser
    MAX_CONFIGURATION_BYTES = 1_048_576
    SCHEMA_VERSION = 1
    SYSTEM_CONFIGURATION_COMPONENT = 'system_configuration'.freeze
    Result = Data.define(:report, :kernel_configuration, :record_events)

    def self.call(raw) = new(raw).call

    def initialize(raw)
      @raw = raw
    end

    def call
      unless supported?
        return invalid_result(
          "unsupported schema version #{reported_schema_version.inspect}; expected #{SCHEMA_VERSION}"
        )
      end

      payload = @raw.deep_dup
      validate!(payload)
      configuration = extract_configuration!(payload)

      Result.new(
        report: Report.from_hash(payload),
        kernel_configuration: configuration,
        record_events: true
      )
    rescue ArgumentError, KeyError, TypeError => e
      invalid_result(e.message)
    end

    protected

    def supported?
      @raw.is_a?(Hash) && @raw['schema_version'] == SCHEMA_VERSION
    end

    def validate!(payload)
      kernel = payload.fetch('kernel')
      raise TypeError, 'kernel must be an object' unless kernel.is_a?(Hash)

      %w[booted_release reported_release].each do |key|
        value = kernel.fetch(key)
        unless value.is_a?(String) && !value.empty?
          raise TypeError, "kernel.#{key} must be a non-empty string"
        end
      end
      %w[boot_id vpsadminos_version vpsadminos_revision kernel_source_revision config_digest].each do |key|
        optional_string!(kernel, key)
      end
      optional_time!(kernel, 'booted_at')

      validate_payload!(payload)
      validate_kernel!(kernel)
      validate_software_versions!(payload)

      %w[livepatches ebpf_programs loaded_modules errors].each do |key|
        raise TypeError, "#{key} must be an array" unless payload.fetch(key).is_a?(Array)
      end
      %w[livepatches ebpf_programs errors].each do |key|
        unless payload.fetch(key).all?(Hash)
          raise TypeError, "#{key} entries must be objects"
        end
      end
      unless payload.fetch('loaded_modules').all?(String)
        raise TypeError, 'loaded_modules entries must be strings'
      end

      unique_values!(payload.fetch('loaded_modules'), 'loaded_modules')

      %w[sysctls deployment].each do |key|
        raise TypeError, "#{key} must be an object" unless payload.fetch(key).is_a?(Hash)
      end
      validate_sysctls!(payload.fetch('sysctls'))

      payload.fetch('livepatches').each { |livepatch| validate_livepatch!(livepatch) }
      unique_keys!(payload.fetch('livepatches'), 'id', 'livepatches')
      payload.fetch('ebpf_programs').each { |program| validate_ebpf_program!(program) }
      unique_keys!(payload.fetch('ebpf_programs'), 'name', 'ebpf_programs')
      payload.fetch('errors').each do |error|
        %w[component reason].each do |key|
          raise TypeError, "errors.#{key} must be a string" unless error[key].is_a?(String)
        end
      end
    end

    def validate_kernel!(kernel)
      digest = kernel['config_digest']
      unless digest.nil? || (digest.is_a?(String) && digest.match?(/\A[0-9a-f]{64}\z/))
        raise TypeError, 'kernel.config_digest must be a lowercase SHA-256 digest or null'
      end

      booted_parameters = kernel.fetch('booted_params', [])
      unless booted_parameters.is_a?(Array) && booted_parameters.all? do |parameter|
               parameter.is_a?(String) && !parameter.empty? && !parameter.start_with?('=')
             end
        raise TypeError, 'kernel.booted_params must be an array of non-empty parameters'
      end

      optional_string!(kernel, 'command_line')
      config_text = kernel['config_text']
      return if config_text.nil? || config_text.is_a?(String)

      raise TypeError, 'kernel.config_text must be a string or null'
    end

    def validate_payload!(payload)
      kernel = payload.fetch('kernel')
      %w[boot_id booted_at kernel_source_revision config_digest command_line].each do |key|
        kernel.fetch(key)
      end
      kernel.fetch('booted_params')
      %w[
        livepatches ebpf_programs deployment loaded_modules sysctls
        errors
      ].each { |key| payload.fetch(key) }

      deployment = payload.fetch('deployment')
      raise TypeError, 'deployment must be an object' unless deployment.is_a?(Hash)

      %w[booted_system current_system].each do |key|
        deployment.fetch(key)
        optional_string!(deployment, key)
      end
    end

    def validate_software_versions!(payload)
      identities = payload.fetch('software_versions')
      unless identities.is_a?(Array) && identities.all?(Hash)
        raise TypeError, 'software_versions must be an array of objects'
      end

      required = %w[booted current].product(%w[vpsadminos vpsadmin nixpkgs])
      optional = %w[booted current].product([SYSTEM_CONFIGURATION_COMPONENT])
      allowed = required + optional
      actual = identities.map do |identity|
        generation = identity.fetch('generation')
        component = identity.fetch('component')
        unless %w[booted current].include?(generation)
          raise TypeError, 'software_versions.generation is invalid'
        end
        unless allowed.any? { |_, allowed_component| allowed_component == component }
          raise TypeError, 'software_versions.component is invalid'
        end

        validate_software_identity!(identity)
        [generation, component]
      end
      unique = actual.uniq
      return if unique.length == actual.length &&
                (required - unique).empty? &&
                (unique - allowed).empty?

      raise TypeError,
            'software_versions must contain every required identity and no duplicate identities'
    end

    def validate_software_identity!(identity)
      %w[version version_source revision revision_source].each do |key|
        optional_string!(identity, key)
      end
      boolean!(identity, 'revision_dirty', 'software_versions')

      if identity['version'].is_a?(String) && identity['version'].empty?
        raise TypeError, 'software_versions.version must not be empty'
      end
      if identity['revision'].is_a?(String) && identity['revision'].empty?
        raise TypeError, 'software_versions.revision must not be empty'
      end
      unless identity['version'].nil? == identity['version_source'].nil?
        raise TypeError, 'software_versions.version_source must accompany version'
      end
      if identity['version_source'] && identity['version_source'] != 'native'
        raise TypeError, 'software_versions.version_source is invalid'
      end
      unless identity['revision'].nil? == identity['revision_source'].nil?
        raise TypeError, 'software_versions.revision_source must accompany revision'
      end
      if identity['revision'] && !identity['revision'].match?(/\A[0-9a-f]{40}\z/)
        raise TypeError, 'software_versions.revision must be a full Git commit hash'
      end
      if identity['revision_source'] && !%w[native confctl].include?(identity['revision_source'])
        raise TypeError, 'software_versions.revision_source is invalid'
      end
      return unless identity['revision_dirty'] && identity['revision_source'] != 'native'

      raise TypeError, 'software_versions.revision_dirty requires a native revision'
    end

    def validate_sysctls!(sysctls)
      sysctls.each do |name, values|
        unless name.is_a?(String) && name.bytesize <= 255 &&
               name.match?(/\A[a-z0-9_-]+(?:\.[a-z0-9_-]+)+\z/i)
          raise TypeError, 'sysctls names must be valid dotted kernel parameter names'
        end
        raise TypeError, "sysctls.#{name} must be an object" unless values.is_a?(Hash)

        values.fetch('configured')
        values.fetch('effective')
        boolean!(values, 'available', "sysctls.#{name}")
        optional_scalar!(values, 'configured', "sysctls.#{name}")
        optional_scalar!(values, 'effective', "sysctls.#{name}")
      end
    end

    def validate_livepatch!(livepatch)
      nonempty_string!(livepatch, 'id', 'livepatch')
      nonempty_string!(livepatch, 'kernel_version', 'livepatch')
      scalar!(livepatch, 'patch_version', 'livepatch')
      %w[loaded enabled transition].each { |key| boolean!(livepatch, key, 'livepatch') }
      optional_time!(livepatch, 'applied_at')
      optional_time!(livepatch, 'verified_at')

      patches = livepatch.fetch('patches')
      raise TypeError, 'livepatch.patches must be an array' unless patches.is_a?(Array)

      patches.each do |patch|
        raise TypeError, 'livepatch.patches entries must be objects' unless patch.is_a?(Hash)

        nonempty_string!(patch, 'name', 'livepatch patch')
        scalar!(patch, 'version', 'livepatch patch')
      end
      unique_keys!(patches, 'name', 'livepatch.patches')
    end

    def validate_ebpf_program!(program)
      %w[name revision digest].each { |key| nonempty_string!(program, key, 'eBPF program') }
      %w[description sinceKernel untilKernel].each do |key|
        optional_string!(program, key)
      end
      boolean!(program, 'active', 'eBPF program')
      optional_time!(program, 'attached_at')
      optional_time!(program, 'verified_at')

      objects = program.fetch('bpfPrograms')
      unless objects.is_a?(Array) && objects.all? { |name| name.is_a?(String) && !name.empty? }
        raise TypeError, 'eBPF program.bpfPrograms must be an array of non-empty strings'
      end

      unique_values!(objects, 'eBPF program.bpfPrograms')

      links = program.fetch('links')
      unless links.is_a?(Hash) && links.all? do |name, attached|
               name.is_a?(String) && !name.empty? && [true, false].include?(attached)
             end
        raise TypeError, 'eBPF program.links must map strings to booleans'
      end

      expected_active = !links.empty? && links.values.all?(true)
      if program['active'] != expected_active
        raise TypeError, 'eBPF program.active must equal the state of all links'
      end
      return unless program['active'] && (!program['attached_at'] || !program['verified_at'])

      raise TypeError, 'active eBPF programs require attachment and verification timestamps'
    end

    def extract_configuration!(payload)
      kernel = payload.fetch('kernel')
      content = kernel.delete('config_text')
      return unless content
      if content.bytesize > MAX_CONFIGURATION_BYTES
        raise ArgumentError, 'kernel.config_text exceeds 1 MiB'
      end

      digest = kernel['config_digest']
      raise ArgumentError, 'kernel.config_digest is required with config_text' unless digest
      unless Digest::SHA256.hexdigest(content) == digest
        raise ArgumentError, 'kernel.config_text does not match config_digest'
      end

      { digest:, content: }
    end

    def unique_values!(values, label)
      return if values.uniq.length == values.length

      raise TypeError, "#{label} entries must be unique"
    end

    def unique_keys!(items, key, label)
      unique_values!(items.map { |item| item.fetch(key) }, label)
    end

    def optional_string!(object, key)
      value = object[key]
      return if value.nil? || value.is_a?(String)

      raise TypeError, "#{key} must be a string or null"
    end

    def nonempty_string!(object, key, prefix)
      value = object.fetch(key)
      return if value.is_a?(String) && !value.empty?

      raise TypeError, "#{prefix}.#{key} must be a non-empty string"
    end

    def scalar!(object, key, prefix)
      value = object.fetch(key)
      return if value.is_a?(String) || value.is_a?(Numeric)

      raise TypeError, "#{prefix}.#{key} must be a scalar"
    end

    def optional_scalar!(object, key, prefix)
      value = object[key]
      return if value.nil? || value.is_a?(String) || value.is_a?(Numeric)
      return if [true, false].include?(value)

      raise TypeError, "#{prefix}.#{key} must be a scalar or null"
    end

    def boolean!(object, key, prefix)
      value = object.fetch(key)
      return if [true, false].include?(value)

      raise TypeError, "#{prefix}.#{key} must be a boolean"
    end

    def optional_time!(object, key)
      value = object[key]
      return if value.nil?
      raise TypeError, "#{key} must be an ISO 8601 string" unless value.is_a?(String)

      Time.iso8601(value)
    rescue ArgumentError
      raise ArgumentError, "#{key} must be an ISO 8601 timestamp"
    end

    def invalid_result(reason)
      Result.new(
        report: Report.invalid(schema_version: invalid_schema_version, reason:),
        kernel_configuration: nil,
        record_events: false
      )
    end

    def reported_schema_version
      @raw.is_a?(Hash) ? @raw['schema_version'] : nil
    end

    def invalid_schema_version
      version = reported_schema_version
      version.is_a?(Integer) ? version : 0
    end
  end
end
