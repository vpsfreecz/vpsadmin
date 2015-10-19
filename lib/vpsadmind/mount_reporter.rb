module VpsAdmind
  class MountReporter
    include Utils::Log

    STATES = [
        :created,
        :mounted,
        :unmounted,
        :skipped,
        :delayed,
        :waiting
    ]

    class << self
      attr_accessor :instance
      
      def report(*args)
        instance.report(*args)
      end
    end
    
    def initialize
      self.class.instance = self

      @mutex = Mutex.new

      # vps_id => [mounts]
      @mounts = []
    end
    
    def start
      @thread = Thread.new do
        db = nil
        misses = 0

        loop do
          mnt = nil
          
          break if @stop

          sync do
            next if @mounts.empty?
            mnt = @mounts.pop
          end

          unless mnt
            misses += 1

            if db && misses >= 5
              log(:debug, :mount_reporter, 'Disconnecting from the database')
              db.close
              db = nil
            end

            sleep(1)
            next
          end

          log(
              :debug,
              :mount_reporter,
              "vps=#{mnt[:vps_id]},mount=##{mnt[:id]},state=#{mnt[:state]}"
          )
          db ||= Db.new
          db.prepared(
              'UPDATE mounts SET current_state = ? WHERE id = ?',
              STATES.index(mnt[:state]), mnt[:id]
          )

          misses = 0
        end
      end
    end

    def stop
      @stop = true
      @thread.join
    end

    def report(vps_id, mount_id, state)
      sync do
        @mounts.delete_if do |mnt|
          mnt[:id] == mount_id
        end

        @mounts << {
            :vps_id => vps_id,
            :id => mount_id,
            :state => state
        }
      end
    end

    protected
    def sync
      @mutex.synchronize { yield }
    end
  end
end
