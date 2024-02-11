module VpsAdmin::CLI::Commands
  class VpsMigrateMany < HaveAPI::CLI::Command
    cmd :vps, :migrate_many
    args 'VPS_ID...'
    desc 'Migrate multiple VPSes using a migration plan'

    def options(opts)
      @opts = {}

      opts.on('--migration-plan PLAN_ID', 'Reuse existing migration plan') do |id|
        @opts[:plan] = id
      end

      opts.on('--dst-node NODE_ID', 'Destination node') do |id|
        @opts[:dst_node] = id.to_i
      end

      opts.on('--[no-]outage-window', 'Migrate VPSes inside outage windows') do |w|
        @opts[:outage_window] = w
      end

      opts.on('--[no-]cleanup-data', 'Cleanup VPS dataset on the source node') do |c|
        @opts[:cleanup_data] = c
      end

      opts.on('--[no-]stop-on-error', 'Cancel the plan if a migration fails') do |s|
        @opts[:stop_on_error] = s
      end

      opts.on('--concurrency N', 'How many migrations run concurrently') do |n|
        @opts[:concurrency] = n.to_i
      end

      opts.on('--[no-]send-mail', 'Send users mail informing about the migration') do |s|
        @opts[:send_mail] = s
      end

      opts.on('--reason REASON', 'Why are the VPS being migrated') do |r|
        @opts[:reason] = r
      end
    end

    def exec(args)
      if args.size < 2
        puts 'provide at least two VPS IDs'
        exit(false)

      elsif @opts[:dst_node].nil?
        puts 'provide --dst-node'
        exit(false)
      end

      puts 'Verifying VPS IDs...'
      vpses = []

      args.each do |vps_id|
        if /^\d+$/ !~ vps_id
          puts "'#{vps_id}' is not a valid VPS ID"
          exit(false)
        end

        vpses << vps_id.to_i
      end

      plan = nil

      begin
        if @opts[:plan]
          puts 'Reusing an existing migration plan...'
          plan = @api.migration_plan.find(@opts[:plan])

          if plan.state != 'staged'
            puts 'Cannot reuse a plan that has already left the staging phase'
            exit(false)
          end

        else
          puts 'Creating a migration plan...'
          plan = @api.migration_plan.create(@opts)
        end
      rescue HaveAPI::Client::ActionFailed => e
        report_error(e)
      end

      puts 'Scheduling VPS migrations...'
      begin
        vpses.each do |vps_id|
          params = {
            vps: vps_id,
            dst_node: @opts[:dst_node]
          }
          params[:outage_window] = @opts[:outage_window] unless @opts[:outage_window].nil?
          params[:cleanup_data] = @opts[:cleanup_data] unless @opts[:cleanup_data].nil?

          plan.vps_migration.create(params)
        end
      rescue HaveAPI::Client::ActionFailed => e
        report_error(e)
      end

      puts 'Executing the migration plan'
      begin
        ret = plan.start
      rescue HaveAPI::Client::ActionFailed => e
        report_error(e)
      end

      HaveAPI::CLI::OutputFormatter.print(ret.attributes)
    end

    protected

    def report_error(e)
      puts e.message

      # FIXME: uncomment this code when ActionFailed makes response accessible
      # if e.response.errors
      #   e.response.errors.each do |param, errs|
      #     puts "  #{param}: #{errs.join('; ')}"
      #   end
      # end

      exit(false)
    end
  end
end
