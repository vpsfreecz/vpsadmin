require_relative '../event'

module NodeCtld
  # Parse OOM killer report from kernel log
  #
  # Important bits:
  #
  #   <comm> invoked oom-killer: gfp_mask=..., order=..., oom_score_adj=...
  #   CPU: <n> PID: <pid> Comm: <comm> ...
  #   ...
  #   memory: usage <n>kB, limit <n>kB, failcnt <n>
  #   memory+swap: usage <n>kB, limit <n>kB, failcnt <n>
  #   kmem: usage <n>kB, limit <n>kB, failcnt <n>
  #   Memory cgroup stats for /osctl/pool.<pool>/group.<group>/user.<user>/ct.<ctid>:
  #   anon <n>\x0afile <n>\x0a ...
  #   Tasks state (memory values in pages):
  #   [  pid  ]   uid  tgid total_vm      rss pgtables_bytes swapents oom_score_adj name
  #
  #   ... follows a list of all tasks ...
  #
  #   Out of memory and no killable processes...
  #
  #   ... or ...
  #
  #   oom-kill:constraint=CONSTRAINT_MEMCG,nodemask=...,cpuset=...,mems_allowed=...,oom_memcg=...,task_memcg=...,task=<comm>,pid=<pid>,uid=<uid>
  #   Memory cgroup out of memory: Killed process <pid> (<comm>) total-vm:<n>kB, anon-rss:<n>kB, file-rss:<n>kB, shmem-rss:<n>kB, UID:<uid> pgtables:<n>kB oom_score_adj:<n>
  #   oom_reaper: reaped process <pid> (<comm>)...
  class KernelLog::OomKill::Event < KernelLog::Event
    def self.start?(msg)
      /^[^\s]+ invoked oom-killer: / =~ msg.text
    end

    attr_reader :report

    def start(msg)
      m = match_or_fail!(/^([^\s]+) invoked oom-killer: /, msg.text)
      @report = KernelLog::OomKill::Report.new(msg.time, m[1])
      log(:info, "OOM killer activity detected, invoked by #{report.invoked_by_name}")
    end

    def <<(msg)
      if !report.invoked_by_pid \
         && /^CPU: \d+ PID: (\d+) Comm:/ =~ msg.text
        report.invoked_by_pid = $1.to_i
        return
      end

      if !report.usage[:mem] \
         && /^memory: usage (\d+)kB, limit (\d+)kB, failcnt (\d+)/ =~ msg.text
        report.usage[:mem] = {
          usage: $1.to_i,
          limit: $2.to_i,
          failcnt: $3.to_i,
        }
        return
      end

      if !report.usage[:memswap] \
         && /^memory\+swap: usage (\d+)kB, limit (\d+)kB, failcnt (\d+)/ =~ msg.text
        report.usage[:memswap] = {
          usage: $1.to_i,
          limit: $2.to_i,
          failcnt: $3.to_i,
        }
        return
      end

      if !report.usage[:kmem] \
         && /^kmem: usage (\d+)kB, limit (\d+)kB, failcnt (\d+)/ =~ msg.text
        report.usage[:kmem] = {
          usage: $1.to_i,
          limit: $2.to_i,
          failcnt: $3.to_i,
        }
        return
      end

      if !report.vps_id \
         && /^Memory cgroup stats for \/osctl\/pool\.([^\/]+)\/group\.([^\/]+)\/user\.([^\/]+)\/ct\.([^:]+):/ =~ msg.text
        vps_id = $4.to_i

        if vps_id == 0
          log(:info, "Skipping OOM report from an unmanaged VPS #{$1}:#{$4}")
          finish!
          return
        end

        report.pool = $1
        report.group = $2
        report.user = $3
        report.vps_id = vps_id
        return
      end

      if report.stats.empty? && /^anon \d+/ =~ msg.text
        msg.text.strip.split("\\x0a").each do |stat|
          k, v = stat.split
          report.stats[k] = v.to_i
        end
        return
      end

      if /^\[\s*(\d+)\] ([^$]+)/ =~ msg.text
        attrs = $2.split
        return if attrs.length != 8

        uid, tgid, total_vm, rss, pgtables_bytes, swapents, oom_score_adj, name = attrs

        report.tasks << {
          pid: $1.to_i,
          uid: uid.to_i,
          tgid: tgid.to_i,
          total_vm: total_vm.to_i,
          rss: rss.to_i,
          pgtables_bytes: pgtables_bytes.to_i,
          swapents: swapents.to_i,
          oom_score_adj: oom_score_adj.to_i,
          name: name,
        }

        return
      end

      if msg.text.start_with?('Out of memory and no killable processes')
        report.no_killable = true
        finish!
        return
      end

      if /^oom_reaper: reaped process (\d+) \(([^\)]+)\)/ =~ msg.text
        report.killed_pid = $1.to_i
        report.killed_name = $2
        finish!
      end
    end

    def lost_messages(count)
      log(:info, "Lost #{count} messages, cancelling report as incomplete")
      finish!
    end

    def close
      if report
        if report.complete?
          log(:info, "Submitting OOM report from VPS #{report.vps_id}")
          report.submit
        else
          log(:info, 'OOM report incomplete, disregarding')
        end
      end
    end

    def log_type
      'oom-event'
    end
  end
end
