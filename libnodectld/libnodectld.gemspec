lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'nodectld/version'

Gem::Specification.new do |s|
  s.name        = 'libnodectld'

  if ENV['VPSADMIN_BUILD_ID']
    s.version   = "#{NodeCtld::VERSION}.build#{ENV['VPSADMIN_BUILD_ID']}"
  else
    s.version   = NodeCtld::VERSION
  end

  s.summary     =
  s.description = 'Daemon for vpsAdmin node'
  s.authors     = 'Jakub Skokan'
  s.email       = 'jakub.skokan@vpsfree.cz'
  s.files       = `git ls-files -z`.split("\x0")
  s.executables = s.files.grep(%r{^bin/}) { |f| File.basename(f) }
  s.license     = 'GPL'

  s.required_ruby_version = '>= 2.0.0'

  s.add_runtime_dependency 'libosctl', ENV['OS_BUILD_ID']
  s.add_runtime_dependency 'osctl', ENV['OS_BUILD_ID']
  s.add_runtime_dependency 'json'
  s.add_runtime_dependency 'mysql2'
  s.add_runtime_dependency 'eventmachine'
  s.add_runtime_dependency 'pry', '~> 0.11.3'
  s.add_runtime_dependency 'pry-remote'
  s.add_runtime_dependency 'require_all', '~> 2.0.0'
  s.add_runtime_dependency 'mail'
  s.add_runtime_dependency 'filelock'
  s.add_runtime_dependency 'ipaddress', '~> 0.8.3'
end
