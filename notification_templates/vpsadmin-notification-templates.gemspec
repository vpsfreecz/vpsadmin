lib = File.expand_path('lib', __dir__)
$:.unshift(lib) unless $:.include?(lib)
require 'vpsadmin/notification_templates/version'

Gem::Specification.new do |s|
  s.name        = 'vpsadmin-notification-templates'
  s.version     = VpsAdmin::NotificationTemplates::VERSION
  s.summary     =
    s.description = 'Notification template installer'
  s.authors     = 'Jakub Skokan'
  s.email       = 'jakub.skokan@vpsfree.cz'
  s.files = Dir[
    'bin/*',
    'lib/**/*'
  ].select { |f| File.file?(f) }
  s.executables = s.files.grep(%r{^bin/}) { |f| File.basename(f) }
  s.license     = 'GPL'

  s.required_ruby_version = ">= #{File.read('../.ruby-version').strip}"

  s.add_dependency 'haveapi-client', '~> 0.28.4'
  s.add_dependency 'highline', '~> 3.1'
end
