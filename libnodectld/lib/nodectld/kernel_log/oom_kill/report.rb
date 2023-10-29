require 'libosctl'

module NodeCtld
  class KernelLog::OomKill::Report
    include OsCtl::Lib::Utils::Log

    attr_reader :time
    attr_accessor :invoked_by_pid, :invoked_by_name
    attr_accessor :usage, :stats
    attr_accessor :tasks
    attr_accessor :pool, :group, :user, :vps_id
    attr_accessor :cgroup
    attr_accessor :killed_pid, :killed_name, :no_killable
    attr_accessor :count

    def initialize(time, invoked_by_name)
      @time = time
      @invoked_by_name = invoked_by_name
      @usage = {}
      @stats = {}
      @tasks = []
      @count = 1
    end

    def complete?
      (invoked_by_pid \
       && invoked_by_name \
       && ((killed_pid && killed_name) || no_killable) \
       && vps_id) ? true : false
    end

    def find_vps_pids_and_uids
      tasks.each do |task|
        task.update(vps_pid: nil, vps_uid: nil)

        begin
          process = OsCtl::Lib::OsProcess.new(task[:pid])
          proc_pool, proc_ctid = process.ct_id
          next if proc_pool.nil? || proc_ctid.to_i != vps_id

          task[:vps_pid] = process.ct_pid

          begin
            task[:vps_uid] = process.ct_ruid if task[:vps_pid]
          rescue OsCtl::Lib::Exceptions::IdMappingError
            # pass
          end

        # Reading /proc/<pid>/uid_map is known to sometimes return EIVAL, but
        # handle all system call errors just in case.
        rescue OsCtl::Lib::Exceptions::OsProcessNotFound, SystemCallError
          next
        end
      end
    end

    def log_type
      'oom-report'
    end

    def export
      {
        vps_id: vps_id,
        cgroup: cgroup,
        invoked_by_pid: invoked_by_pid,
        invoked_by_name: invoked_by_name,
        killed_pid: killed_pid,
        killed_name: killed_name,
        count: count,
        time: time.to_i,
        usage: usage,
        stats: stats,
        tasks: tasks,
      }
    end
  end
end
