require 'erb'
require 'singleton'

module DistConfig
  class ErbTemplateCache
    class << self
      def [](name)
        instance[name]
      end
    end

    include Singleton

    def initialize
      @templates = {}
      load
    end

    def load
      templates.clear

      tpl_dir = File.realpath(File.join(File.dirname(__FILE__), '../../templates'))

      Dir.glob('**/*.erb', base: tpl_dir).each do |tpl|
        content = File.read(File.join(tpl_dir, tpl))
        templates[tpl[0..-5]] = ERB.new(content, trim_mode: '-')
      end
    end

    # @param name [String]
    # @return [ERB]
    def [](name)
      templates[name].clone
    end

    protected

    attr_reader :templates
  end
end
