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

    def initialize(id)
      @id = id
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

    def rollback(step)
      Migrator.rollback_plugin(self, step)
    end
  end
end
