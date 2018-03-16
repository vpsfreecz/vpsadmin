module NodeCtld
  STANDALONE = true unless const_defined?(:STANDALONE)
end

if NodeCtld::STANDALONE
  require_relative '../nodectld'

  $CFG = NodeCtld::AppConfig.new(ENV['CONFIG'] || '/etc/vpsadmin/nodectld.yml')

  exit(false) unless $CFG.load(ENV['DB_CONFIG'])
end
