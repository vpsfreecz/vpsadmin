namespace :vpsadmin do
  namespace :outage_reports do
    desc 'Auto-resolve announced outage reports'
    task :auto_resolve do
      now = Time.now

      min_duration = ENV['MIN_DURATION'] ? ENV['MIN_DURATION'].to_i : 15 * 60
      delay = ENV['DELAY'] ? ENV['DELAY'].to_i : 10 * 60

      ::Outage.where(state: 'announced', auto_resolve: true).each do |outage|
        resolve = false

        if outage.finished_at
          resolve = true if outage.finished_at < now

        elsif outage.begins_at \
              && outage.begins_at + outage.duration * 60 + delay < now \
              && now - outage.begins_at > min_duration \
              && outage.outage_updates.count <= 2 # one update for staged, one for announced
          resolve = true
        end

        if resolve
          puts "Auto-resolving outage ##{outage.id}"
          outage.do_auto_resolve
        end
      end
    end
  end
end
