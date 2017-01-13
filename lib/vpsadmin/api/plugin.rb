module VpsAdmin::API
  module Plugin
    @plugins = {}

    def self.register(id, &block)
      p = self::Plugin.new(id, &block)
      p.instance_exec(&block)
      p.directory(File.join(VpsAdmin::API.root, 'plugins', id.to_s)) if p.directory.nil?

      @plugins[id.to_sym] = p
    end

    def self.registered
      @plugins
    end
  end
end
