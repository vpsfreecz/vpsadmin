lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'vpsadmin/mail-templates/version'

Gem::Specification.new do |s|
  s.name        = 'vpsadmin-mail-templates'
  s.version     = VpsAdmin::MailTemplates::VERSION
  s.summary     =
  s.description = 'Mail template installer'
  s.authors     = 'Jakub Skokan'
  s.email       = 'jakub.skokan@vpsfree.cz'
  s.files       = `git ls-files -z`.split("\x0")
  s.executables = s.files.grep(%r{^bin/}) { |f| File.basename(f) }
  s.license     = 'GPL'

  s.required_ruby_version = '>= 2.0.0'

  s.add_runtime_dependency 'haveapi-client', '~> 0.15.0'
  s.add_runtime_dependency 'highline', '~> 2.0.3'
end
