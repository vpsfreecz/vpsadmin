require 'pathname'

module VpsAdmin::API::Plugin
  class Loader
    @loaded_components = {}

    # @param component [String] name of a plugin component to load
    def self.load(component)
      component = component.to_s
      return if plugins_disabled?
      return if @loaded_components.has_key?(component)

      plugin_dir = find_plugin_dir
      return unless plugin_dir

      allowed = allowed_plugins

      Dir.entries(plugin_dir).select do |v|
        v != '.' && v != '..' && File.directory?(File.join(plugin_dir, v))
      end.each do |p|
        next if allowed && !allowed.include?(p)

        plugin = VpsAdmin::API::Plugin.catch_plugin do
          Kernel.load(File.join(plugin_dir, p, 'meta.rb'))
        end

        plugin.configure(component)

        next if plugin.components.nil? || !plugin.components.include?(component.to_sym)

        if component == 'api' && plugin.directory.nil?
          plugin.directory(File.join(plugin_dir, p))
        end

        basedir = File.join(plugin_dir, p, component)
        raise "Plugin dir '#{basedir}' not found" unless Dir.exist?(basedir)

        begin
          init = File.realpath(File.join(basedir, 'init.rb'))
        rescue Errno::ENOENT
          %w[lib models resources].each do |d|
            path = File.join(basedir, d)
            require_all(File.realpath(path)) if File.exist?(path)
          end
        else
          Kernel.load(init)
        end
      end

      @loaded_components[component] = true
    end

    def self.plugins_disabled?
      ENV['VPSADMIN_PLUGINS'].to_s.strip.downcase == 'none'
    end
    private_class_method :plugins_disabled?

    def self.allowed_plugins
      mode = ENV['VPSADMIN_PLUGINS'].to_s.strip.downcase
      return nil if mode.empty? || mode == 'all'

      mode.split(',').map(&:strip).reject(&:empty?)
    end
    private_class_method :allowed_plugins

    def self.find_plugin_dir
      env = ENV['VPSADMIN_PLUGIN_DIR'].to_s.strip
      unless env.empty?
        path = env
        path = File.expand_path(path, VpsAdmin::API.root) unless Pathname.new(path).absolute?
        return File.realpath(path) if Dir.exist?(path)
      end

      [
        File.join(VpsAdmin::API.root, 'plugins'),
        File.join(VpsAdmin::API.root, '..', 'plugins')
      ].each do |candidate|
        return File.realpath(candidate) if Dir.exist?(candidate)
      end

      nil
    end
    private_class_method :find_plugin_dir
  end
end
