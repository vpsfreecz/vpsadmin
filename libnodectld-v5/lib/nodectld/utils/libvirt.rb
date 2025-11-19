require 'base64'
require 'json'
require 'rexml'

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

    def distconfig(domain, command, input: nil, run: false, timeout: 60)
      env = [
        'LANG=en_US.UTF-8',
        'LOCALE_ARCHIVE=/run/current-system/sw/lib/locale/locale-archive',
        'PATH=/run/current-system/sw/bin'
      ]

      unless domain.active?
        raise "Domain #{domain.name} is not active" unless run

        spawned = true

        domain = add_domain_kernel_parameter(domain, 'vpsadmin.distconfig')
        domain.create

        wait_for_guest_agent(domain, timeout:)
      end

      ret = vmexec(domain, %w[distconfig] + command, env:, input:, timeout:)
      return ret unless spawned

      domain.destroy
      remove_domain_kernel_parameter(domain, 'vpsadmin.distconfig')

      ret
    end

    def distconfig!(*, **)
      ret = distconfig(*, **)
      return ret if ret[0] == 0

      raise "distconfig failed with #{ret[0]}: #{ret[2].inspect}"
    end

    # @param domain [Libvirt::Domain]
    # @param param [String]
    # @return [Libvirt::Domain]
    def add_domain_kernel_parameter(domain, param)
      doc = REXML::Document.new(domain.xml_desc)

      os_elem = REXML::XPath.first(doc, '/domain/os')
      raise 'No <os> element in domain XML' unless os_elem

      cmdline_elem = REXML::XPath.first(doc, '/domain/os/cmdline')
      raise 'No <cmdline> element in domain XML' unless cmdline_elem

      current = cmdline_elem.text.to_s.strip
      params = current.empty? ? [] : current.split(/\s+/)

      return domain if params.include?(param)

      params << param
      cmdline_elem.text = params.join(' ')

      domain.connection.define_domain_xml(doc.to_s)
    end

    # @param domain [Libvirt::Domain]
    # @param param [String]
    # @return [Libvirt::Domain]
    def remove_domain_kernel_parameter(domain, param)
      doc = REXML::Document.new(domain.xml_desc)

      cmdline_elem = REXML::XPath.first(doc, '/domain/os/cmdline')
      return domain unless cmdline_elem && cmdline_elem.text

      current = cmdline_elem.text.to_s.strip
      params = current.split(/\s+/)
      new_params = params.reject { |p| p == param }

      return domain if new_params == params

      cmdline_elem.text = new_params.join(' ')

      domain.connection.define_domain_xml(doc.to_s)
    end

    # @param domain [Libvirt::Domain]
    # @param param [String]
    # @param value [String]
    # @return [Libvirt::Domain]
    def set_domain_kernel_parameter(domain, param, value)
      doc = REXML::Document.new(domain.xml_desc)

      os_elem = REXML::XPath.first(doc, '/domain/os')
      raise 'No <os> element in domain XML' unless os_elem

      cmdline_elem = REXML::XPath.first(doc, '/domain/os/cmdline')
      raise 'No <cmdline> element in domain XML' unless cmdline_elem

      current = cmdline_elem.text.to_s.strip
      params = current.empty? ? [] : current.split(/\s+/)
      replaced = false

      new_params = params.map do |p|
        k, v = p.split('=', 2)
        next p if k != param

        replaced = true
        "#{param}=#{value}"
      end

      new_params << "#{param}=#{value}" unless replaced

      return domain if new_params == params

      cmdline_elem.text = new_params.join(' ')

      domain.connection.define_domain_xml(doc.to_s)
    end

    def wait_for_guest_agent(domain, timeout:)
      t = Time.now

      loop do
        if timeout && t + timeout < Time.now
          raise 'Timed out while waiting for the guest agent'
        end

        begin
          domain.qemu_agent_command({ 'execute' => 'guest-ping' }.to_json)
        rescue Libvirt::Error
          sleep(0.5)
          next
        else
          return true
        end
      end
    end
  end
end
