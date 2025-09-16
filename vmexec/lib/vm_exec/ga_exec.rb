require 'base64'
require 'json'

module VmExec
  class GaExec
    def self.run(*, **)
      new.ga_exec(*, **)
    end

    def ga_exec(domain, command)
      cmd = command[0]
      args = command[1..]

      cmd_r, cmd_w = IO.pipe

      cmd_pid = Process.spawn(
        'virsh',
        'qemu-agent-command',
        domain,
        {
          'execute' => 'guest-exec',
          'arguments' => {
            'path' => cmd,
            'arg' => args,
            'capture-output' => true
          }
        }.to_json,
        out: cmd_w
      )

      cmd_w.close

      job_pid = JSON.parse(cmd_r.read)['return']['pid'].to_i

      if job_pid <= 0
        raise 'Bad job pid'
      end

      cmd_r.close

      Process.wait(cmd_pid)

      if $?.exitstatus != 0
        raise "Command failed with #{$?.exitstatus}"
      end

      loop do
        res_r, res_w = IO.pipe

        result_pid = Process.spawn(
          'virsh',
          'qemu-agent-command',
          domain,
          {
            'execute' => 'guest-exec-status',
            'arguments' => {
              'pid' => job_pid
            }
          }.to_json,
          out: res_w
        )

        res_w.close

        result = JSON.parse(res_r.read)['return']

        res_r.close

        Process.wait(result_pid)

        if $?.exitstatus != 0
          raise "Result failed with #{$?.exitstatus}"
        end

        unless result['exited']
          sleep(1)
          next
        end

        return [
          result['exitcode'],
          result['out-data'] && Base64.decode64(result['out-data']),
          result['err-data'] && Base64.decode64(result['err-data'])
        ]
      end
    end
  end
end
