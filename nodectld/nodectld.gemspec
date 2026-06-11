lib = File.expand_path('../libnodectld/lib', __dir__)
$:.unshift(lib) unless $:.include?(lib)
require 'nodectld/version'

Gem::Specification.new do |s|
  s.name = 'nodectld'

  s.version = NodeCtld::VERSION

  s.summary     =
    s.description = 'Daemon for vpsAdmin node'
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

  s.add_dependency 'libnodectld', s.version
end
