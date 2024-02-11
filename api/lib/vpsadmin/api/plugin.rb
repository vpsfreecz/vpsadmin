module VpsAdmin::API
  module Plugin
    @plugins = {}

    def self.register(id, &)
      p = self::Plugin.new(id, &)

      @plugins[id.to_sym] = p
      throw(:plugin, p) if @throw
    end

    def self.catch_plugin(&)
      @throw = true
      ret = catch(:plugin, &)
      @throw = false
      ret
    end

    def self.registered
      @plugins
    end
  end

  module Plugins; end
end
