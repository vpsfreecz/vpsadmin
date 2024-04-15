lib = File.expand_path('lib', __dir__)
$:.unshift(lib) unless $:.include?(lib)
require 'vpsadmin/mail_templates/version'

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

  s.required_ruby_version = ">= #{File.read('../.ruby-version').strip}"

  s.add_runtime_dependency 'haveapi-client', '~> 0.22.1'
  s.add_runtime_dependency 'highline', '~> 2.1.0'
end
