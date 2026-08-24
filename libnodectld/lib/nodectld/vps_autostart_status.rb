# frozen_string_literal: true

module NodeCtld
  class VpsAutostartStatus
    class UnsupportedResponse < StandardError; end

    Unsatisfied = Struct.new(:pool, :vps_id, :reason)
    Mismatch = Struct.new(
      :pool,
      :vps_id,
      :vpsadmin,
      :osctld
    )
    Snapshot = Struct.new(
      :success,
      :last_success_at,
      :expected,
      :unsatisfied,
      :unsatisfied_counts,
      :mismatches
    )

    def initialize
      @mutex = Mutex.new
      @snapshot = build_snapshot(success: false, last_success_at: 0)
    end

    # @param vpses [Array<Hash>] rows returned by list_vps_status_check
    # @param containers [Array<OsCtlContainer>] current osctld containers
    # @param now [Time]
    def update(vpses, containers, now: Time.now)
      unless vpses.all? { |vps| vps.has_key?('autostart_enable') }
        raise UnsupportedResponse,
              'list_vps_status_check response does not include autostart_enable'
      end

      containers_by_pool_and_id = containers.to_h do |ct|
        [[ct.pool.to_s, ct.id.to_s], ct]
      end
      expected = Hash.new(0)
      unsatisfied = []
      mismatches = []

      vpses.each do |vps|
        pool = pool_name(vps.fetch('pool_fs'))
        vps_id = vps.fetch('id').to_s.dup.freeze
        ct = containers_by_pool_and_id[[pool, vps_id]]
        desired_autostart = vps.fetch('autostart_enable')

        if ct && desired_autostart != ct.autostart
          mismatches << Mismatch.new(
            pool:,
            vps_id:,
            vpsadmin: boolean_label(desired_autostart),
            osctld: boolean_label(ct.autostart)
          ).freeze
        end

        next unless desired_autostart

        expected[pool] += 1
        next if ct&.runtime_state == 'running'

        unsatisfied << Unsatisfied.new(
          pool:,
          vps_id:,
          reason: ct ? ct.runtime_state.to_s.dup.freeze : 'missing'
        ).freeze
      end

      unsatisfied.sort_by! { |vps| [vps.pool, vps.vps_id] }
      mismatches.sort_by! { |vps| [vps.pool, vps.vps_id] }
      counts = unsatisfied.each_with_object(Hash.new(0)) do |vps, ret|
        ret[[vps.pool, vps.reason].freeze] += 1
      end

      replace_snapshot(
        build_snapshot(
          success: true,
          last_success_at: now.to_i,
          expected:,
          unsatisfied:,
          unsatisfied_counts: counts,
          mismatches:
        )
      )
    end

    def failed
      replace_snapshot(
        build_snapshot(
          success: false,
          last_success_at: snapshot.last_success_at
        )
      )
    end

    def snapshot
      @mutex.synchronize { @snapshot }
    end

    protected

    def replace_snapshot(new_snapshot)
      @mutex.synchronize { @snapshot = new_snapshot }
      new_snapshot
    end

    def build_snapshot(
      success:,
      last_success_at:,
      expected: {},
      unsatisfied: [],
      unsatisfied_counts: {},
      mismatches: []
    )
      Snapshot.new(
        success:,
        last_success_at:,
        expected: expected.to_h.freeze,
        unsatisfied: unsatisfied.freeze,
        unsatisfied_counts: unsatisfied_counts.to_h.freeze,
        mismatches: mismatches.freeze
      ).freeze
    end

    def pool_name(pool_fs)
      pool_fs.split('/', 2).fetch(0).freeze
    end

    def boolean_label(value)
      value ? 'enabled' : 'disabled'
    end
  end
end
