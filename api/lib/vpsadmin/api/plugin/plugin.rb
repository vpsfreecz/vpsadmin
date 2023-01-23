module VpsAdmin::API::Plugin
  class Plugin
    attr_reader :id

    %i(name author email version description url directory).each do |field|
      define_method(field) do |v = nil|
        if v
          instance_variable_set("@#{field}", v)
        else
          instance_variable_get("@#{field}")
        end
      end
    end

    def initialize(id, &block)
      @id = id
      @config = block
    end

    def configure(type)
      @type = type
      instance_exec(&@config)
    end

    def config(&block)
      block.call if @type == 'api'
    end

    def components(*args)
      return @components if args.empty?
      @components = args
    end

    def migration_directory
      File.join(directory, 'api', 'db', 'migrate')
    end

    def migrations
      Dir[File.join(migration_directory, '*.rb')].map do |v|
        File.basename(v).match(/^(\d+)\_/)[1].to_i
      end.sort
    end

    def migrate(version = nil)
      Migrator.migrate_plugin(self, version || migrations.last)
    end

    def rollback(steps)
      Migrator.rollback_plugin(self, steps)
    end
  end
end
