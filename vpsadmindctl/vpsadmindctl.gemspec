lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'vpsadmindctl/version'

Gem::Specification.new do |s|
  s.name        = 'vpsadmindctl'
  s.version     = VpsAdmindCtl::VERSION
  s.summary     =
  s.description = 'Control program for vpsAdmind'
  s.authors     = 'Jakub Skokan'
  s.email       = 'jakub.skokan@vpsfree.cz'
  s.files       = `git ls-files -z`.split("\x0")
  s.license     = 'GPL'

  s.required_ruby_version = '>= 2.0.0'

  s.add_runtime_dependency 'json'
  s.add_runtime_dependency 'pry-remote'
end
