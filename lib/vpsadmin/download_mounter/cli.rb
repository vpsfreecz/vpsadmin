module VpsAdmin::DownloadMounter
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
      usage = <<END
Usage: #{$0} [options] <api> <mountpoint> <action>

Actions:
    auth                             Authenticate and exit
    mount                            Check and mount all download datasets
    umount                           Check and unmount all download datasets

Options:
END

      opt_parser = OptionParser.new do |opts|
        opts.banner = usage

        opts.on('-d', '--dry-run', 'Dry run') do
          @opts[:dry_run] = true
        end
        
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

      if ARGV.size < 3
        puts opt_parser
        exit(1)
      end

      @api = HaveAPI::Client::Client.new(
          ARGV[0],
          identity: "vpsadmin-download-mounter v#{VpsAdmin::DownloadMounter::VERSION}"
      )
      
      authenticate
      
      case ARGV[2]
      when 'auth'
        u = @api.user.current
        puts "Authenticated as #{u.login} (level #{u.level})"

        begin
          @api.pool.list(limit: 0)
          puts "Sufficient permissions for download mount management"
          true

        rescue HaveAPI::Client::ActionFailed => e
          puts "Insufficient permissions for download mount management"
          false
        end

      when 'mount'
        each_pool_mounter { |m| m.mount }

      when 'umount', 'unmount'
        each_pool_mounter { |m| m.umount }

      else
        fail "unsupported action '#{ARGV[2]}'"
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
              # FIXME: this is a workaround until the client has an API that exposes
              # the token.
              token = @api.instance_variable_get('@api') \
                      .instance_variable_get('@auth') \
                      .instance_variable_get('@token')
              
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

    def each_pool_mounter
      @api.pool.list(meta: {includes: 'node__environment'}).each do |pool|
        puts "Pool #{pool.filesystem} of #{pool.node.domain_name}"

        yield(VpsAdmin::DownloadMounter::Mounter.new(@opts, ARGV[1], pool))

        puts "\n"
      end
    end
  end
end
