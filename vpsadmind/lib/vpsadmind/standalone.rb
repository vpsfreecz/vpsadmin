module VpsAdmind
  STANDALONE = true unless const_defined?(:STANDALONE)
end

if VpsAdmind::STANDALONE
  require_relative '../vpsadmind'
        
  $CFG = VpsAdmind::AppConfig.new(ENV['CONFIG'] || '/etc/vpsadmin/vpsadmind.yml')

  exit(false) unless $CFG.load(ENV['DB_CONFIG'])
end
