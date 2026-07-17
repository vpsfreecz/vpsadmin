require 'digest'
require 'json'

module VpsAdmin::API::KernelEvidence
  Kernel = Data.define(
    :boot_id,
    :booted_at,
    :booted_release,
    :reported_release,
    :source_revision,
    :config_digest,
    :booted_parameters,
    :command_line
  )

  Deployment = Data.define(:booted_system, :current_system)
  LivepatchPatch = Data.define(:name, :version)
  Livepatch = Data.define(
    :id,
    :kernel_version,
    :patch_version,
    :loaded,
    :enabled,
    :transition,
    :applied_at,
    :verified_at,
    :patches
  )
  EbpfProgram = Data.define(
    :name,
    :description,
    :since_kernel,
    :until_kernel,
    :revision,
    :digest,
    :active,
    :attached_at,
    :verified_at,
    :objects,
    :links
  ) do
    def change_state
      to_h.except(:verified_at)
    end
  end
  SoftwareVersion = Data.define(
    :generation,
    :component,
    :version,
    :version_source,
    :revision,
    :revision_source,
    :revision_dirty
  ) do
    def key = [generation, component]
  end
  Sysctl = Data.define(:available, :configured, :effective)
  Error = Data.define(:component, :reason)

  class Report
    attr_reader :schema_version,
                :kernel,
                :livepatches,
                :ebpf_programs,
                :deployment,
                :software_versions,
                :loaded_modules,
                :sysctls,
                :errors

    def self.from_hash(value)
      raise TypeError, 'report must be an object' unless value.is_a?(Hash)

      kernel = object(value.fetch('kernel'), 'kernel')
      deployment = object(value.fetch('deployment'), 'deployment')

      new(
        schema_version: value.fetch('schema_version'),
        kernel: Kernel.new(
          boot_id: kernel.fetch('boot_id'),
          booted_at: kernel.fetch('booted_at'),
          booted_release: kernel.fetch('booted_release'),
          reported_release: kernel.fetch('reported_release'),
          source_revision: kernel.fetch('kernel_source_revision'),
          config_digest: kernel.fetch('config_digest'),
          booted_parameters: string_array(
            kernel.fetch('booted_params'),
            'kernel.booted_params'
          ).freeze,
          command_line: kernel.fetch('command_line')
        ),
        livepatches: normalize_livepatches(value.fetch('livepatches')),
        ebpf_programs: normalize_ebpf_programs(value.fetch('ebpf_programs')),
        deployment: Deployment.new(
          booted_system: deployment.fetch('booted_system'),
          current_system: deployment.fetch('current_system')
        ),
        software_versions: normalize_software_versions(value.fetch('software_versions')),
        loaded_modules: string_array(value.fetch('loaded_modules'), 'loaded_modules')
                        .uniq.sort.freeze,
        sysctls: normalize_sysctls(value.fetch('sysctls')),
        errors: array(value.fetch('errors'), 'errors').map do |error|
          error = object(error, 'errors entry')
          Error.new(component: error.fetch('component'), reason: error.fetch('reason'))
        end.sort_by { |error| [error.component, error.reason] }.freeze
      )
    end

    def self.invalid(schema_version:, reason:)
      new(
        schema_version:,
        kernel: Kernel.new(
          boot_id: nil,
          booted_at: nil,
          booted_release: nil,
          reported_release: nil,
          source_revision: nil,
          config_digest: nil,
          booted_parameters: [].freeze,
          command_line: nil
        ),
        livepatches: [].freeze,
        ebpf_programs: [].freeze,
        deployment: Deployment.new(booted_system: nil, current_system: nil),
        software_versions: [].freeze,
        loaded_modules: [].freeze,
        sysctls: {}.freeze,
        errors: [Error.new(
          component: 'security_evidence',
          reason: "invalid: #{reason}"
        )].freeze
      )
    end

    def self.normalize_livepatches(value)
      keyed_items(value, 'id', 'livepatches').map do |item|
        Livepatch.new(
          id: item.fetch('id'),
          kernel_version: item.fetch('kernel_version'),
          patch_version: scalar_string(item.fetch('patch_version')),
          loaded: item.fetch('loaded'),
          enabled: item.fetch('enabled'),
          transition: item.fetch('transition'),
          applied_at: item['applied_at'],
          verified_at: item['verified_at'],
          patches: keyed_items(item.fetch('patches'), 'name', 'livepatch patches').map do |patch|
            LivepatchPatch.new(
              name: patch.fetch('name'),
              version: scalar_string(patch.fetch('version'))
            )
          end.freeze
        )
      end.freeze
    end

    def self.normalize_ebpf_programs(value)
      keyed_items(value, 'name', 'eBPF programs').map do |item|
        EbpfProgram.new(
          name: item.fetch('name'),
          description: item['description'],
          since_kernel: item['sinceKernel'],
          until_kernel: item['untilKernel'],
          revision: item.fetch('revision'),
          digest: item.fetch('digest'),
          active: item.fetch('active'),
          attached_at: item['attached_at'],
          verified_at: item['verified_at'],
          objects: string_array(item.fetch('bpfPrograms'), 'eBPF program objects')
                   .uniq.sort.freeze,
          links: object(item.fetch('links'), 'eBPF program links').sort.to_h.freeze
        )
      end.freeze
    end

    def self.normalize_software_versions(value)
      array(value, 'software_versions').to_h do |raw_item|
        item = object(raw_item, 'software_versions entry')
        generation = item.fetch('generation')
        component = item.fetch('component')
        key = [generation, component]
        [
          key,
          SoftwareVersion.new(
            generation:,
            component:,
            version: item.fetch('version'),
            version_source: item.fetch('version_source'),
            revision: item.fetch('revision'),
            revision_source: item.fetch('revision_source'),
            revision_dirty: item.fetch('revision_dirty')
          )
        ]
      end.values.sort_by do |item|
        [
          ::NodeSoftwareVersion.generations.fetch(item.generation.to_s),
          ::NodeSoftwareVersion.components.fetch(item.component.to_s)
        ]
      end.freeze
    end

    def self.normalize_sysctls(value)
      object(value, 'sysctls').to_h do |name, raw_setting|
        setting = object(raw_setting, "sysctls.#{name}")
        [
          name,
          Sysctl.new(
            available: setting.fetch('available'),
            configured: scalar_string(setting.fetch('configured')),
            effective: scalar_string(setting.fetch('effective'))
          )
        ]
      end.freeze
    end

    def self.scalar_string(value) = value.nil? ? nil : value.to_s

    def self.keyed_items(value, key, label)
      array(value, label).to_h do |raw_item|
        item = object(raw_item, "#{label} entry")
        [item.fetch(key), item]
      end
           .values
           .sort_by { |item| item.fetch(key) }
    end

    def self.object(value, label)
      raise TypeError, "#{label} must be an object" unless value.is_a?(Hash)

      value
    end

    def self.array(value, label)
      raise TypeError, "#{label} must be an array" unless value.is_a?(Array)

      value
    end

    def self.string_array(value, label)
      values = array(value, label)
      raise TypeError, "#{label} entries must be strings" unless values.all?(String)

      values.dup
    end

    private_class_method :normalize_livepatches,
                         :normalize_ebpf_programs,
                         :normalize_software_versions,
                         :normalize_sysctls,
                         :scalar_string,
                         :keyed_items,
                         :object,
                         :array,
                         :string_array

    def initialize(
      schema_version:,
      kernel:,
      livepatches:,
      ebpf_programs:,
      deployment:,
      software_versions:,
      loaded_modules:,
      sysctls:,
      errors:
    )
      @schema_version = schema_version
      @kernel = kernel
      @livepatches = livepatches
      @ebpf_programs = ebpf_programs
      @deployment = deployment
      @software_versions = software_versions
      @loaded_modules = loaded_modules
      @sysctls = sysctls
      @errors = errors
      freeze
    end

    def digest
      Digest::SHA256.hexdigest(JSON.generate(canonical(to_h)))
    end

    def to_h
      {
        'schema_version' => schema_version,
        'kernel' => {
          'boot_id' => kernel.boot_id,
          'booted_at' => kernel.booted_at,
          'booted_release' => kernel.booted_release,
          'reported_release' => kernel.reported_release,
          'kernel_source_revision' => kernel.source_revision,
          'config_digest' => kernel.config_digest,
          'booted_params' => kernel.booted_parameters,
          'command_line' => kernel.command_line
        },
        'livepatches' => livepatches.map do |livepatch|
          {
            'id' => livepatch.id,
            'kernel_version' => livepatch.kernel_version,
            'patch_version' => livepatch.patch_version,
            'loaded' => livepatch.loaded,
            'enabled' => livepatch.enabled,
            'transition' => livepatch.transition,
            'applied_at' => livepatch.applied_at,
            'verified_at' => livepatch.verified_at,
            'patches' => livepatch.patches.map do |patch|
              { 'name' => patch.name, 'version' => patch.version }
            end
          }
        end,
        'ebpf_programs' => ebpf_programs.map do |program|
          {
            'name' => program.name,
            'description' => program.description,
            'sinceKernel' => program.since_kernel,
            'untilKernel' => program.until_kernel,
            'revision' => program.revision,
            'digest' => program.digest,
            'active' => program.active,
            'attached_at' => program.attached_at,
            'verified_at' => program.verified_at,
            'bpfPrograms' => program.objects,
            'links' => program.links
          }
        end,
        'deployment' => {
          'booted_system' => deployment.booted_system,
          'current_system' => deployment.current_system
        },
        'software_versions' => software_versions.map do |software|
          {
            'generation' => software.generation,
            'component' => software.component,
            'version' => software.version,
            'version_source' => software.version_source,
            'revision' => software.revision,
            'revision_source' => software.revision_source,
            'revision_dirty' => software.revision_dirty
          }
        end,
        'loaded_modules' => loaded_modules,
        'sysctls' => sysctls.to_h do |name, setting|
          [
            name,
            {
              'available' => setting.available,
              'configured' => setting.configured,
              'effective' => setting.effective
            }
          ]
        end,
        'errors' => errors.map do |error|
          { 'component' => error.component, 'reason' => error.reason }
        end
      }
    end

    def ==(other) = other.is_a?(self.class) && to_h == other.to_h
    alias eql? ==

    def hash = to_h.hash

    protected

    def canonical(value)
      case value
      when Hash
        value.keys.sort.to_h { |key| [key, canonical(value[key])] }
      when Array
        value.map { |item| canonical(item) }
      else
        value
      end
    end
  end
end
