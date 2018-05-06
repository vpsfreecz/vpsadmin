require 'optparse'
require 'highline/import'
require 'haveapi/client'

module VpsAdmin::MailTemplates
  class Cli
    def self.run
      c = Cli.new
      exit(c.parse ? true : false)
    end

    def initialize
      @opts = {
        auth: 'token',
        lifetime: 'renewable_auto',
      }
    end

    def parse
      usage = <<EOF
Usage: #{$0} [options] <api> <action>

Actions:
    auth                             Authenticate and exit
    install                          Upload templates to the API

Options:
EOF

      opt_parser = OptionParser.new do |opts|
        opts.banner = usage

        opts.on('-a', '--auth AUTH', %w(basic token), 'Basic or token authentication') do |a|
          @opts[:auth] = a
        end

        opts.on('-u', '--user USER', 'Username') do |u|
          @opts[:user] = u
        end

        opts.on('-p', '--password PASSWORD', 'Password') do |p|
          @opts[:password] = p
        end

        opts.on('-t', '--token TOKEN', 'Token') do |t|
          @opts[:token] = t
        end

        opts.on('-i', '--token-lifetime LIFETIME',
                %w(renewable_manual renewable_auto fixed permanent), 'Token lifetime') do |l|
          @opts[:lifetime] = l
        end

        opts.on('-s', '--save-token [FILE]', 'Save token to FILE') do |f|
          @opts[:save] = f || 'auth.token'
          @opts[:auth] = 'token'
        end

        opts.on('-l', '--load-token [FILE]', 'Load token from FILE') do |f|
          @opts[:load] = f || 'auth.token'
          @opts[:auth] = 'token'
        end

        opts.on('-h', '--help', 'Show this help') do
          puts opts
          exit
        end
      end

      opt_parser.parse!

      if ARGV.size < 2
        puts opt_parser
        exit(1)
      end

      @api = HaveAPI::Client::Client.new(
        ARGV[0],
        identity: "vpsadmin-mail-templates v#{VpsAdmin::MailTemplates::VERSION}"
      )

      authenticate

      case ARGV[1]
      when 'auth'
        u = @api.user.current
        puts "Authenticated as #{u.login} (level #{u.level})"

        begin
          @api.mail_template.list(limit: 0)
          puts "Sufficient permissions for mail template management"
          true

        rescue HaveAPI::Client::ActionFailed => e
          puts "Insufficient permissions for mail template management"
          false
        end

      when 'install'
        VpsAdmin::MailTemplates.install(@api)

      else
        fail "unsupported action '#{ARGV[1]}'"
      end
    end

    def authenticate
      if @opts[:auth] == 'basic'
        u, p = get_credentials
        @api.authenticate(:basic, user: u, password: p)

      elsif @opts[:auth] == 'token'
        token = @opts[:token]

        unless token
          if @opts[:load]
            @api.authenticate(:token, token: File.new(@opts[:load]).read.strip)

          else
            u, p = get_credentials
            @api.authenticate(:token, user: u, password: p, lifetime: @opts[:lifetime])

            if @opts[:save]
              token = @api.auth.token

              f = File.new(@opts[:save], 'w')
              f.write(token)
              f.close
            end
          end
        end

      else
        fail "unsupported auth"
      end
    end

    def get_credentials
      @opts[:user] ||= ask('Username: ') { |q| q.default = nil }.to_s

      @opts[:password] ||= ask('Password: ') do |q|
        q.default = nil
        q.echo = false
      end.to_s

      [@opts[:user], @opts[:password]]
    end
  end
end
