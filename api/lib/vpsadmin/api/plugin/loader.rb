module VpsAdmin::API::Plugin
  class Loader
    # @param component [String] name of a plugin component to load
    def self.load(component)
      plugin_dir = File.realpath(File.join(
        VpsAdmin::API.root,
        'plugins'
      ))
      return unless File.exists?(plugin_dir)

      Dir.entries(plugin_dir).select do |v|
        v != '.' && v != '..' && File.directory?(File.join(plugin_dir, v))
      end.each do |p|
        plugin = VpsAdmin::API::Plugin.catch_plugin do
          Kernel.load(File.join(plugin_dir, p, 'meta.rb'))
        end

        plugin.configure(component)

        next if plugin.components.nil? || !plugin.components.include?(component.to_sym)

        if component == 'api'
          if plugin.directory.nil?
            plugin.directory(File.join(VpsAdmin::API.root, 'plugins', plugin.id.to_s))
          end
        end

        basedir = File.join(plugin_dir, p, component)
        fail "Plugin dir '#{basedir}' not found" unless Dir.exists?(basedir)

        init = File.join(basedir, 'init.rb')

        if File.exists?(init)
          Kernel.load(init)

        else
          %w(lib models resources).each do |d|
            path = File.join(basedir, d)
            require_all(File.realpath(path)) if File.exists?(path)
          end
        end
      end
    end
  end
end
