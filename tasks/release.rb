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
      'nodectld/lib/nodectld/version.rb',
      'nodectl/lib/nodectl/version.rb',
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

  desc 'Close changelog for the latest version'
  task :close_changelog do
    v = File.read('VERSION').strip
    header = "* #{Time.now.strftime('%a %b %d %Y')} - version #{v}"

    (Dir.glob('*/CHANGELOG') + Dir.glob('plugins/*/CHANGELOG')).each do |file|
      io = File.open(file, 'r')
      first = io.readline
      io.close

      if first.start_with?('* ')
        # Changelog already closed
        if first.include?("version #{v}")
          puts "#{file}: already closed"
          next
        end

        # No change has been logged
        puts "#{file}: closing with no changes"
        File.write(
          file,
          "#{header}\n- No changes\n\n" + File.read(file)
        )
      elsif first.start_with?('- ')
        puts "#{file}: closing"
        File.write(
          file,
          "#{header}\n" + File.read(file)
        )

      else
        puts "#{file}: invalid first line, ignoring"
      end
    end
  end

  desc 'Build gems and deploy to rubygems'
  task :gems do
    build_id = Time.now.strftime('%Y%m%d%H%M%S')

    begin
      os = File.realpath(ENV['OS'] || '../vpsadminos')

    rescue Errno::ENOENT
      warn "vpsAdminOS not found at '#{ENV['OS'] || '../vpsadminos'}'"
      exit(false)
    end

    os_build_id_path = File.join(os, '.build_id')

    begin
      os_build_id = File.read(os_build_id_path)

    rescue Errno::ENOENT
      warn "vpsAdminOS build ID not found at '#{os_build_id_path}'"
      exit(false)
    end

    %w(libnodectld nodectld nodectl).each do |gem|
      ret = system('./tools/update_gem.sh', 'packages', gem, build_id, os_build_id)
      unless ret
        fail "unable to build #{gem}: failed with exit status #{$?.exitstatus}"
      end
    end
  end
end
