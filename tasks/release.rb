namespace :vpsadmin do
  desc 'Set vpsAdmin version'
  task :version do
    unless ENV['VERSION']
      fail "missing required environment variable VERSION"
    end

    v = ENV['VERSION'].strip

    File.write("VERSION", "#{v}\n")

    [
      'vpsadmind/lib/vpsadmind/version.rb',
      'vpsadmindctl/lib/vpsadmindctl/version.rb',
      'console_router/lib/vpsadmin/console_router/version.rb',
      'client/lib/vpsadmin/client/version.rb',
      'download_mounter/lib/vpsadmin/download_mounter/version.rb',
      'api/lib/vpsadmin/api/version.rb',
      'mail_templates/lib/vpsadmin/mail-templates/version.rb',
    ].each do |file|
      File.write(file, File.read(file).sub(/ VERSION = '[^']+'/, " VERSION = '#{v}'"))
    end

    Dir.glob('plugins/*/meta.rb').each do |file|
      File.write(file, File.read(file).sub(/ version '[^']+'/, " version '#{v}'"))
    end

    webui = 'webui/lib/version.lib.php'
    File.write(
      webui,
      File.read(webui).sub(/define\("VERSION", '[^']+'\);/, "define(\"VERSION\", '#{v}');")
    )
  end
end
