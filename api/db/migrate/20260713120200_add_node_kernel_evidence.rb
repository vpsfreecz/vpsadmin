class AddNodeKernelEvidence < ActiveRecord::Migration[8.1]
  def up
    create_table :node_kernel_evidences, **evidence_table_options do |t|
      t.references :node, null: false
      t.integer :snapshot_type, null: false
      t.integer :report_schema_version, null: false
      t.datetime :observed_at, null: false
      t.datetime :received_at, null: false
      t.string :snapshot_revision, limit: 64, null: false
      t.string :boot_id, limit: 64
      t.datetime :booted_at
      t.string :booted_release, limit: 128
      t.string :reported_release, limit: 128
      t.string :kernel_source_revision, limit: 128
      t.string :kernel_config_digest, limit: 64
      t.text :kernel_command_line
      t.string :booted_system, limit: 512
      t.string :current_system, limit: 512
      t.timestamps
    end

    add_index :node_kernel_evidences, %i[node_id snapshot_type]
    add_index :node_kernel_evidences, :snapshot_revision
    add_index :node_kernel_evidences, :kernel_config_digest

    create_table :node_kernel_parameters, **evidence_table_options do |t|
      evidence_reference(t)
      t.integer :position, null: false
      t.string :name, null: false
      t.text :value
    end
    add_index :node_kernel_parameters,
              %i[node_kernel_evidence_id position],
              unique: true,
              name: :idx_node_kernel_parameters_position
    add_index :node_kernel_parameters,
              %i[name node_kernel_evidence_id],
              name: :idx_node_kernel_parameters_lookup

    create_named_component_table(:node_kernel_modules)

    create_table :node_sysctls, **evidence_table_options do |t|
      evidence_reference(t)
      t.string :name, null: false
      t.boolean :available, null: false
      t.text :configured_value
      t.text :effective_value
    end
    add_component_indexes(:node_sysctls, :name)

    create_table :node_software_versions, **evidence_table_options do |t|
      evidence_reference(t)
      t.integer :generation, null: false
      t.integer :component, null: false
      t.string :version, limit: 128
      t.integer :version_source
      t.string :revision, limit: 128
      t.integer :revision_source
      t.boolean :revision_dirty, null: false, default: false
    end
    add_index :node_software_versions,
              %i[node_kernel_evidence_id generation component],
              unique: true,
              name: :idx_node_software_versions_unique
    add_index :node_software_versions,
              %i[component generation node_kernel_evidence_id],
              name: :idx_node_software_versions_lookup

    create_table :node_sysctl_changes, **evidence_table_options do |t|
      event_reference(t)
      t.string :name, null: false
      t.boolean :before_available
      t.text :before_configured_value
      t.text :before_effective_value
      t.boolean :after_available
      t.text :after_configured_value
      t.text :after_effective_value
    end
    add_index :node_sysctl_changes,
              %i[node_kernel_event_id name],
              unique: true,
              name: :idx_node_sysctl_changes_unique
    add_index :node_sysctl_changes,
              %i[name node_kernel_event_id],
              name: :idx_node_sysctl_changes_lookup

    create_table :node_software_changes, **evidence_table_options do |t|
      event_reference(t)
      t.integer :generation, null: false
      t.integer :component, null: false
      t.string :before_version, limit: 128
      t.string :before_version_source, limit: 16
      t.string :before_revision, limit: 128
      t.string :before_revision_source, limit: 16
      t.boolean :before_revision_dirty, null: false, default: false
      t.string :after_version, limit: 128
      t.string :after_version_source, limit: 16
      t.string :after_revision, limit: 128
      t.string :after_revision_source, limit: 16
      t.boolean :after_revision_dirty, null: false, default: false
    end
    add_index :node_software_changes,
              %i[node_kernel_event_id generation component],
              unique: true,
              name: :idx_node_software_changes_unique
    add_index :node_software_changes,
              %i[component generation node_kernel_event_id],
              name: :idx_node_software_changes_lookup

    create_table :node_kernel_livepatches, **evidence_table_options do |t|
      evidence_reference(t)
      t.string :livepatch_id, null: false
      t.string :kernel_version, limit: 128
      t.string :patch_version, limit: 128
      t.boolean :loaded
      t.boolean :enabled
      t.boolean :transition
      t.datetime :applied_at
      t.datetime :verified_at
    end
    add_component_indexes(:node_kernel_livepatches, :livepatch_id)

    create_table :node_kernel_livepatch_patches, **evidence_table_options do |t|
      t.references :node_kernel_livepatch,
                   null: false,
                   foreign_key: { on_delete: :cascade },
                   index: false
      t.string :name, null: false
      t.string :version, limit: 128
    end
    add_index :node_kernel_livepatch_patches,
              %i[node_kernel_livepatch_id name],
              unique: true,
              name: :idx_node_kernel_livepatch_patches_unique
    add_index :node_kernel_livepatch_patches,
              %i[name node_kernel_livepatch_id],
              name: :idx_node_kernel_livepatch_patches_lookup

    create_table :node_ebpf_programs, **evidence_table_options do |t|
      evidence_reference(t)
      t.string :name, null: false
      t.text :description
      t.string :since_kernel, limit: 128
      t.string :until_kernel, limit: 128
      t.string :revision, limit: 128
      t.string :digest, limit: 128
      t.boolean :active, null: false
      t.datetime :attached_at
      t.datetime :verified_at
    end
    add_component_indexes(:node_ebpf_programs, :name)

    create_table :node_ebpf_program_objects, **evidence_table_options do |t|
      t.references :node_ebpf_program,
                   null: false,
                   foreign_key: { on_delete: :cascade },
                   index: false
      t.string :name, null: false
    end
    add_index :node_ebpf_program_objects,
              %i[node_ebpf_program_id name],
              unique: true,
              name: :idx_node_ebpf_program_objects_unique
    add_index :node_ebpf_program_objects,
              %i[name node_ebpf_program_id],
              name: :idx_node_ebpf_program_objects_lookup

    create_table :node_ebpf_program_links, **evidence_table_options do |t|
      t.references :node_ebpf_program,
                   null: false,
                   foreign_key: { on_delete: :cascade },
                   index: false
      t.string :name, null: false
      t.boolean :attached, null: false
    end
    add_index :node_ebpf_program_links,
              %i[node_ebpf_program_id name],
              unique: true,
              name: :idx_node_ebpf_program_links_unique
    add_index :node_ebpf_program_links,
              %i[name node_ebpf_program_id],
              name: :idx_node_ebpf_program_links_lookup

    create_table :node_kernel_evidence_errors, **evidence_table_options do |t|
      evidence_reference(t)
      t.string :component, null: false
      t.text :reason, null: false
    end
    add_index :node_kernel_evidence_errors,
              %i[node_kernel_evidence_id component],
              name: :idx_node_kernel_evidence_errors_component

    add_reference :node_current_statuses,
                  :node_kernel_evidence,
                  index: { unique: true },
                  foreign_key: { on_delete: :nullify }
    add_reference :node_kernel_events,
                  :node_kernel_evidence,
                  foreign_key: { on_delete: :nullify }
  end

  # Rails' inferred rollback removes explicit composite indexes before their
  # foreign keys. MySQL refuses that ordering, so dependencies are removed in
  # reverse order explicitly.
  def down
    remove_reference :node_kernel_events, :node_kernel_evidence
    remove_reference :node_current_statuses, :node_kernel_evidence
    drop_table :node_kernel_evidence_errors
    drop_table :node_ebpf_program_links
    drop_table :node_ebpf_program_objects
    drop_table :node_ebpf_programs
    drop_table :node_kernel_livepatch_patches
    drop_table :node_kernel_livepatches
    drop_table :node_software_changes
    drop_table :node_sysctl_changes
    drop_table :node_software_versions
    drop_table :node_sysctls
    drop_table :node_kernel_modules
    drop_table :node_kernel_parameters
    drop_table :node_kernel_evidences
  end

  protected

  def create_named_component_table(table)
    create_table table, **evidence_table_options do |t|
      evidence_reference(t)
      t.string :name, null: false
    end
    add_component_indexes(table, :name)
  end

  def evidence_reference(table)
    table.references :node_kernel_evidence,
                     null: false,
                     foreign_key: { on_delete: :cascade },
                     index: false
  end

  def event_reference(table)
    table.references :node_kernel_event,
                     null: false,
                     foreign_key: { on_delete: :cascade },
                     index: false
  end

  # Kernel and eBPF identifiers are case-sensitive. For example, Linux can
  # load both xt_DSCP and xt_dscp, which collide under the database default
  # Czech case-insensitive collation.
  def evidence_table_options
    { charset: 'utf8mb3', collation: 'utf8mb3_bin' }
  end

  def add_component_indexes(table, key)
    prefix = table.to_s.singularize.sub(/^node_/, '')
    add_index table,
              [:node_kernel_evidence_id, key],
              unique: true,
              name: "idx_node_#{prefix}_unique"
    add_index table,
              [key, :node_kernel_evidence_id],
              name: "idx_node_#{prefix}_lookup"
  end
end
