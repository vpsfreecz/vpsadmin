lib = File.expand_path('lib', __dir__)
$:.unshift(lib) unless $:.include?(lib)
require 'nodectl/version'

Gem::Specification.new do |s|
  s.name = 'nodectl'

  s.version = NodeCtl::VERSION

  s.summary     =
    s.description = 'CLI for nodectld'
  s.authors     = 'Jakub Skokan'
  s.email       = 'jakub.skokan@vpsfree.cz'
  s.files       = Dir[
    'bin/*',
    'lib/**/*',
    'man/man?/*.?',
    'templates/**/*'
  ].select { |f| File.file?(f) }
  s.executables = s.files.grep(%r{^bin/}) { |f| File.basename(f) }
  s.license     = 'GPL'

  s.required_ruby_version = ">= #{File.read('../.ruby-version').strip}"

  s.add_dependency 'json'
  s.add_dependency 'libnodectld', s.version
  s.add_dependency 'libosctl', ENV.fetch('VPSADMINOS_GEM_VERSION', nil)
  s.add_dependency 'pry', '~> 0.14.2'
  s.add_dependency 'pry-remote'
  s.add_dependency 'require_all', '~> 2.0.0'
end
