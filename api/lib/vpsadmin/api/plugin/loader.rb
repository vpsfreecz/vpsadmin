module VpsAdmin::API::Plugin
  class Loader
    # @param component [String] name of a plugin component to load
    def self.load(component)
      plugin_dir = File.realpath(File.join(
                                   VpsAdmin::API.root,
                                   'plugins'
                                 ))
      return unless File.exist?(plugin_dir)

      Dir.entries(plugin_dir).select do |v|
        v != '.' && v != '..' && File.directory?(File.join(plugin_dir, v))
      end.each do |p|
        plugin = VpsAdmin::API::Plugin.catch_plugin do
          Kernel.load(File.join(plugin_dir, p, 'meta.rb'))
        end

        plugin.configure(component)

        next if plugin.components.nil? || !plugin.components.include?(component.to_sym)

        if component == 'api' && plugin.directory.nil?
          plugin.directory(File.join(VpsAdmin::API.root, 'plugins', plugin.id.to_s))
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
    end
  end
end
