require 'json'
require 'singleton'

module VpsAdmin::API
  class DeploymentConfig
    include Singleton

    def self.dig(*keys)
      instance.dig(*keys)
    end

    def self.reload!
      instance.reload!
    end

    def initialize
      @path = File.join(VpsAdmin::API.root, 'config', 'deployment.json')
    end

    def reload!
      remove_instance_variable(:@load) if instance_variable_defined?(:@load)
      self
    end

    def dig(*keys)
      current = load

      keys.each do |key|
        return nil unless current.is_a?(Hash)

        current = current[key.to_s]
      end

      current
    end

    protected

    attr_reader :path

    def load
      return @load if defined?(@load)

      @load = if File.exist?(path)
                parse(File.read(path))
              else
                {}
              end
    end

    def parse(contents)
      data = JSON.parse(contents)

      unless data.is_a?(Hash)
        raise VpsAdmin::API::Exceptions::ConfigurationError,
              'deployment.json must contain a JSON object'
      end

      data
    rescue JSON::ParserError => e
      raise VpsAdmin::API::Exceptions::ConfigurationError,
            "Unable to parse deployment.json: #{e.message}"
    end
  end
end
