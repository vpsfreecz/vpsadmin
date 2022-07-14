require 'libosctl'
require 'singleton'
require 'thread'

module NodeCtld
  class Bird
    ROOT_CONFIG = '/run/bird/vpsadmin.conf'

    include Singleton
    include OsCtl::Lib::Utils::Log
    include OsCtl::Lib::Utils::File
    include Utils::System
    include Utils::Pool

    # Generate root configuration file
    def self.configure(pool_filesystems)
      instance.configure(pool_filesystems)
    end

    # Reload bird configuration
    def self.reconfigure
      instance.reconfigure
    end

    def initialize
      @mutex = Mutex.new
    end

    def configure(pool_filesystems)
      sync do
        regenerate_file(ROOT_CONFIG, 0644) do |new|
          pool_filesystems.each do |fs|
            bird_conf_dir = File.join('/', fs, path_to_pool_working_dir(:config), 'bird')
            new.puts("include \"#{bird_conf_dir}/*.conf\";")
          end
        end
      end
    end

    def reconfigure
      sync do
        syscmd('birdc configure')
      end
    end

    protected
    def sync(&block)
      @mutex.synchronize(&block)
    end
  end
end
