module VpsAdmin::API
  module Plugin
    @plugins = {}

    def self.register(id, &block)
      p = self::Plugin.new(id, &block)

      @plugins[id.to_sym] = p
      throw(:plugin, p) if @throw
    end

    def self.catch_plugin(&block)
      @throw = true
      ret = catch(:plugin, &block)
      @throw = false
      ret
    end

    def self.registered
      @plugins
    end
  end

  module Plugins; end
end
