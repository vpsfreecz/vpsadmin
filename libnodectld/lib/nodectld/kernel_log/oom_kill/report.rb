require 'libosctl'

module NodeCtld
  class KernelLog::OomKill::Report
    include OsCtl::Lib::Utils::Log

    attr_reader :time
    attr_accessor :invoked_by_pid, :invoked_by_name
    attr_accessor :usage, :stats
    attr_accessor :tasks
    attr_accessor :pool, :group, :user, :vps_id
    attr_accessor :killed_pid, :killed_name

    def initialize(time, invoked_by_name)
      @time = time
      @invoked_by_name = invoked_by_name
      @usage = {}
      @stats = {}
      @tasks = []
    end

    def complete?
      (invoked_by_pid && invoked_by_name && killed_pid && killed_name && vps_id) ? true : false
    end

    def submit
      find_vps_pids_and_uids
      save
    end

    def log_type
      'oom-report'
    end

    protected
    def find_vps_pids_and_uids
      tasks.each do |task|
        begin
          process = OsCtl::Lib::OsProcess.new(task[:pid])
          proc_pool, proc_ctid = process.ct_id
          next if proc_pool.nil? || proc_ctid.to_i != vps_id
        rescue OsCtl::Lib::Exceptions::OsProcessNotFound
          next
        end

        task[:vps_pid] = process.ct_pid
        task[:vps_uid] = process.ct_ruid if task[:vps_pid]
      end
    end

    def save
      db = Db.new
      report_id = nil

      db.transaction do |t|
        t.prepared(
          'INSERT INTO oom_reports SET
            vps_id = ?,
            invoked_by_pid = ?,
            invoked_by_name = ?,
            killed_pid = ?,
            killed_name = ?,
            created_at = ?
          ',
          vps_id,
          invoked_by_pid, invoked_by_name[0..49],
          killed_pid, killed_name[0..49],
          time.utc.strftime('%Y-%m-%d %H:%M:%S')
        )

        report_id = t.insert_id

        usage.each do |type, attrs|
          t.prepared(
            'INSERT INTO oom_report_usages SET
              `oom_report_id` = ?,
              `memtype` = ?,
              `usage` = ?,
              `limit` = ?,
              `failcnt` = ?
            ', report_id, type.to_s, attrs[:usage], attrs[:limit], attrs[:failcnt]
          )
        end

        stats.each do |k, v|
          t.prepared(
            'INSERT INTO oom_report_stats SET
              `oom_report_id` = ?,
              `parameter` = ?,
              `value` = ?
            ', report_id, k, v
          )
        end

        tasks.each do |task|
          t.prepared(
            'INSERT INTO oom_report_tasks SET
              `oom_report_id` = ?,
              `host_pid` = ?,
              `vps_pid` = ?,
              `name` = ?,
              `host_uid` = ?,
              `vps_uid` = ?,
              `tgid` = ?,
              `total_vm` = ?,
              `rss` = ?,
              `pgtables_bytes` = ?,
              `swapents` = ?,
              `oom_score_adj` = ?
            ', report_id,
            task[:pid], task[:vps_pid], task[:name][0..49],
            task[:uid], task[:vps_uid], task[:tgid],
            task[:total_vm], task[:rss], task[:pgtables_bytes], task[:swapents],
            task[:oom_score_adj]
          )
        end
      end

      db.close
      log(:info, "Submitted OOM report ##{report_id} from VPS #{vps_id}")
    end
  end
end
