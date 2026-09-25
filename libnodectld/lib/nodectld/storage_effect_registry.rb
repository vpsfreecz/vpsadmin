# frozen_string_literal: true

# The strict support states are evaluated only by explicit Command test
# injection. Production dispatch remains in observer mode.
module NodeCtld
  class StorageEffectRegistry
    VERSION = 4
    EFFECT_CLASSES = %i[
      no_storage read_only data_or_property_write bounded_topology opaque_topology
    ].freeze
    VERIFICATION_IMPACTS = %i[none dependency catalog_identity physical_topology].freeze
    STRICT_SUPPORT_STATES = %i[proved_no_storage_effect guarded_5204_v1 guarded_5215_v1 unsupported].freeze
    Entry = Data.define(
      :execute, :rollback, :execute_impact, :rollback_impact,
      :admission_required, :scope_resolver, :guard_version, :support,
      :execute_strict_support, :rollback_strict_support
    )

    DEPENDENCY_IMPACT = %w[
      5216 5219 5225 5226 5227 5228 5301 5302 5303
      5401 5402 5403 5404 5405 5406 5407
    ].map!(&:to_i).freeze
    CATALOG_IDENTITY_IMPACT = [5224].freeze
    CONSERVATIVE_TOPOLOGY_IMPACT = [7001, 7002].freeze

    NO_STORAGE = %w[
      101 102 2006 2007 2012 2026 2101 2102 2201
      5501 5502 5503 5504 5505 5506 5507 5508 5510
      9001 10001
    ].map!(&:to_i).freeze

    # These write configuration, files or runtime state. Gate them conservatively
    # during read_only even though they do not prove a topology graph change.
    OFF_GRAPH_DATA = %w[
      2002 2003 2004 2005 2013 2016 2017 2018 2019 2022 2023
      2027 2028 2030 2031 2032 2033 2035 2036
      4005 4006 5004 5005 5261 5262 5263 5264 5301
      5401 5402 5403 5404 5405 5406 5407 7001 7002
    ].map!(&:to_i).freeze

    STORAGE_DATA = %w[
      5216 5219 5224 5226 5227 5228 5229 5302 5303
    ].map!(&:to_i).freeze
    READ_ONLY = %w[5221 5222 5290].map!(&:to_i).freeze
    BOUNDED_TOPOLOGY = [5204].freeze
    OPAQUE_TOPOLOGY = %w[
      1001 1002 1003 2020 2029 2034
      3001 3002 3003 3030 3031 3032 3033 3034 3035 3040 3041 3303
      5201 5203 5206 5207 5208 5209 5211 5212 5213 5214 5215
      5217 5218 5220 5223 5230 5250 8001
    ].map!(&:to_i).freeze

    # A direction is classified even when the handler has no rollback method.
    ROLLBACK_OVERRIDES = {
      1003 => :no_storage,
      2029 => :no_storage,
      3034 => :no_storage,
      3031 => :no_storage,
      3303 => :no_storage,
      5212 => :no_storage,
      5221 => :no_storage,
      5222 => :no_storage,
      5228 => :no_storage,
      5229 => :no_storage,
      5290 => :no_storage
    }.freeze
    EXECUTE_OVERRIDES = { 3035 => :no_storage }.freeze

    def self.impact_for(handle, effect)
      return :none if %i[no_storage read_only].include?(effect)
      return :catalog_identity if CATALOG_IDENTITY_IMPACT.include?(handle)
      return :dependency if DEPENDENCY_IMPACT.include?(handle)
      return :physical_topology if CONSERVATIVE_TOPOLOGY_IMPACT.include?(handle)
      return :physical_topology if %i[bounded_topology opaque_topology].include?(effect)

      :none
    end

    def self.journal_impact(entry)
      VERIFICATION_IMPACTS.reverse.find do |impact|
        [entry.execute_impact, entry.rollback_impact].include?(impact)
      end
    end

    def self.strict_support_for(handle, effect)
      return :proved_no_storage_effect if %i[no_storage read_only].include?(effect)
      return :guarded_5204_v1 if handle == 5204
      return :guarded_5215_v1 if handle == 5215

      :unsupported
    end

    ENTRIES = begin
      groups = {
        no_storage: [NO_STORAGE, false],
        data_or_property_write: [OFF_GRAPH_DATA, true],
        storage_data: [STORAGE_DATA, true],
        read_only: [READ_ONLY, false],
        bounded_topology: [BOUNDED_TOPOLOGY, true],
        opaque_topology: [OPAQUE_TOPOLOGY, true]
      }
      entries = {}
      groups.each do |group, (handles, admit)|
        effect = group == :storage_data ? :data_or_property_write : group
        handles.each do |handle|
          raise "duplicate storage effect handle #{handle}" if entries.has_key?(handle)

          execute = EXECUTE_OVERRIDES.fetch(handle, effect)
          rollback = ROLLBACK_OVERRIDES.fetch(handle, effect)
          execute_impact = impact_for(handle, execute)
          rollback_impact = impact_for(handle, rollback)
          journal_impact = VERIFICATION_IMPACTS.reverse.find do |impact|
            [execute_impact, rollback_impact].include?(impact)
          end
          entries[handle] = Entry.new(
            execute, rollback, execute_impact, rollback_impact,
            admit,
            if handle == 5204
              :snapshot_create
            elsif journal_impact == :physical_topology
              :node_pools
            elsif journal_impact == :none
              :none
            else
              :owner_pool
            end,
            [5204, 5215].include?(handle) ? 1 : nil,
            :paired,
            strict_support_for(handle, execute), strict_support_for(handle, rollback)
          )
        end
      end
      entries.freeze
    end

    class Unclassified < StandardError; end

    def self.fetch!(handle)
      ENTRIES.fetch(handle.to_i) { raise Unclassified, "unclassified storage effect handle #{handle}" }
    end
  end
end
