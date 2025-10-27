require 'base64'
require 'json'

module NodeCtld
  module Utils::Libvirt
    SYSTEM_PATH = %w[
      /bin
      /usr/bin
      /sbin
      /usr/sbin
      /run/current-system/sw/bin
      /nix/var/nix/profiles/system/sw/bin
      /run/current-system/profile/bin
      /run/current-system/profile/sbin
      /var/guix/profiles/system/profile/bin
      /var/guix/profiles/system/profile/sbin
    ].freeze

    def vmexec(domain, command, env: [], input: nil, timeout: 60)
      t1 = Time.now

      cmd = command[0].to_s
      args = command[1..].map(&:to_s)

      exec_args = {
        'path' => cmd,
        'arg' => args,
        'env' => env,
        'capture-output' => true
      }

      exec_args['input-data'] = Base64.encode64(input) if input

      job_json = domain.qemu_agent_command({
        'execute' => 'guest-exec',
        'arguments' => exec_args
      }.to_json)

      job_pid = JSON.parse(job_json)['return']['pid'].to_i

      loop do
        status_json = domain.qemu_agent_command({
          'execute' => 'guest-exec-status',
          'arguments' => {
            'pid' => job_pid
          }
        }.to_json)

        status = JSON.parse(status_json)
        result = status['return']

        unless result['exited']
          raise 'Timeout' if t1 + timeout < Time.now

          sleep(0.1)
          next
        end

        return [
          result['exitcode'],
          result['out-data'] && Base64.decode64(result['out-data']),
          result['err-data'] && Base64.decode64(result['err-data'])
        ]
      end

      raise 'programming error'
    end

    def vmctexec(domain, command, timeout: 60)
      vmexec(
        domain,
        %W[lxc-attach -n vps -v PATH=#{SYSTEM_PATH.join(':')} --] + command,
        timeout:
      )
    end

    def distconfig(domain, command, input: nil, timeout: 60)
      env = [
        'LANG=en_US.UTF-8',
        'LOCALE_ARCHIVE=/run/current-system/sw/lib/locale/locale-archive',
        'PATH=/run/current-system/sw/bin'
      ]

      vmexec(domain, %w[distconfig] + command, env:, input:, timeout:)
    end

    def distconfig!(*, **)
      ret = distconfig(*, **)
      return ret if ret[0] == 0

      raise "distconfig failed with #{ret[0]}: #{ret[2].inspect}"
    end
  end
end
