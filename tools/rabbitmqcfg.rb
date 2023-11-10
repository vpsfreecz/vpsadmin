#!/usr/bin/env ruby
# Generate rabbitmqctl commands to configure the cluster
require 'optparse'

class Cli
  ACTIONS = %w(setup user policies)

  USERS = %w(console node supervisor)

  def self.run(args)
    cli = new(args)
    cli.run
  end

  def initialize(args)
    @args = args
  end

  def run
    @execute = false
    @host = nil
    @vhost = 'vpsadmin_dev'
    @user_all = true
    @user_create = false
    @user_perms = false

    @parser = OptionParser.new do |parser|
      parser.banner = <<END
Usage:
  #{$0} user [--create] [--perms] console|node|supervisor <name...>
  #{$0} policies
END
      parser.on('--execute', 'Execute configuration commands') do
        @execute = true
      end

      parser.on('--host HOST', 'Execute configuration commands over ssh') do |v|
        @host = v
      end

      parser.on('-p', '--vhost VHOST', 'Virtual host') do |v|
        @vhost = v
      end

      parser.on('--create', 'Create user') do
        @user_all = false
        @user_create = true
      end

      parser.on('--perms', 'Set permissions') do
        @user_all = false
        @user_perms = true
      end
    end

    cmd_args = @parser.parse!(@args)

    if cmd_args.length < 1
      warn "Missing action"
      warn @parser.help
      exit(false)
    elsif !ACTIONS.include?(cmd_args[0])
      warn "Unknown action #{cmd_args[0].inspect}, expected one of #{ACTIONS.join(', ')}"
      warn @parser.help
      exit(false)
    end

    send(:"run_#{cmd_args[0]}", cmd_args[1..])
  end

  protected
  def run_setup(_args)
    print_or_execute([
      "rabbitmqctl add_vhost #{@vhost}",
      "rabbitmqctl add_user admin",
      "rabbitmqctl set_permissions -p #{@vhost} admin \".*\" \".*\" \".*\"",
      "rabbitmqctl set_user_tags admin administrator",
    ])
  end

  def run_user(args)
    if args.length < 2
      warn "Missing user type / name"
      warn @parser.help
      exit(false)
    end

    type, *users = args

    unless USERS.include?(type)
      warn "Unknown user type #{type.inspect}, expected one of #{USERS.join(', ')}"
      warn @parser.help
      exit(false)
    end

    users.each do |user|
      if @user_all || @user_create
        print_or_execute(["rabbitmqctl add_user #{user}"])
      end

      if @user_all || @user_perms
        print_or_execute(<<END)
rabbitmqctl set_permissions \\
  -p #{@vhost} \\
  #{user} \\
  #{user_perms(type, user).map{ |v| "\"#{v}\"" }.join(" \\\n  ")}
END
      end
    end
  end

  def user_perms(type, user)
    case type
    when 'console'
      [
        "^(amq\\.gen.*|console:rpc|console:output:.+|console:[^:]+:(input|output))$",
        "^(amq\\.gen.*|console:rpc|console:output:.+|console:[^:]+:(input|output))$",
        "^(amq\\.gen.*|console:rpc|console:output:.+|console:[^:]+:(input|output))$",
      ]
    when 'node'
      rx_name = Regexp.escape(user)

      [
        "^(amq\\.gen.*|node:#{rx_name}|console:#{rx_name}:.+)$",
        "^(amq\\.gen.*|node:#{rx_name}|console:#{rx_name}:.+)$",
        "^(amq\\.gen.*|node:#{rx_name}|node:#{rx_name}:.+|console:#{rx_name}:input)$",
      ]
    when 'supervisor'
      [".*", ".*", ".*"]
    else
      ["^$", "^$", "^$"]
    end
  end

  def run_policies(_args)
    print_or_execute(<<END)
rabbitmqctl set_policy \\
	-p #{@vhost} \\
	TTL \\
	"^node:[^:]+:(statuses|net_monitor|pool_statuses|storage_statuses|vps_statuses|vps_os_processes|vps_ssh_host_keys)$" \\
	'{"message-ttl":60000}' \\
	--apply-to queues
END

  print_or_execute(<<END)
rabbitmqctl set_policy \\
	-p #{@vhost} \\
	console-output \\
	"console:output:.+" \\
	'{"max-length": 1000,"max-length-bytes":#{32*1024*1024},"overflow":"drop-head","expires":600000,"message-ttl":60000}' \\
	--apply-to queues
END
  end

  def print_or_execute(arg)
    cmds =
      if arg.is_a?(String)
        [arg]
      elsif arg.respond_to?(:each)
        arg
      else
        raise ArgumentError, "expected argument to be String or respond to #each"
      end

    cmds.each do |cmd|
      exec_cmd =
        if @host
          "ssh -l root #{@host} '#{cmd}'"
        else
          cmd
        end

      puts exec_cmd

      if @execute && !Kernel.system(exec_cmd)
        fail "Command #{exec_cmd.inspect} failed"
      end

      puts
    end
  end
end

Cli.run(ARGV)
