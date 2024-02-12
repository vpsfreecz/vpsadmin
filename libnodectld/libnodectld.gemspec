lib = File.expand_path('lib', __dir__)
$:.unshift(lib) unless $:.include?(lib)
require 'nodectld/version'

Gem::Specification.new do |s|
  s.name = 'libnodectld'

  s.version = if ENV['VPSADMIN_BUILD_ID']
                "#{NodeCtld::VERSION}.build#{ENV['VPSADMIN_BUILD_ID']}"
              else
                NodeCtld::VERSION
              end

  s.summary     =
    s.description = 'Daemon for vpsAdmin node'
  s.authors     = 'Jakub Skokan'
  s.email       = 'jakub.skokan@vpsfree.cz'
  s.files       = `git ls-files -z`.split("\x0")
  s.executables = s.files.grep(%r{^bin/}) { |f| File.basename(f) }
  s.license     = 'GPL'

  s.required_ruby_version = '>= 3.2.0'

  s.add_runtime_dependency 'bunny', '~> 2.22.0'
  s.add_runtime_dependency 'filelock'
  s.add_runtime_dependency 'ipaddress', '~> 0.8.3'
  s.add_runtime_dependency 'json'
  s.add_runtime_dependency 'libosctl', ENV.fetch('OS_BUILD_ID')
  s.add_runtime_dependency 'mail', '~> 2.8.1'
  s.add_runtime_dependency 'mysql2', '0.5.5'
  s.add_runtime_dependency 'osctl', ENV.fetch('OS_BUILD_ID')
  s.add_runtime_dependency 'osctl-exportfs', ENV.fetch('OS_BUILD_ID')
  s.add_runtime_dependency 'prometheus-client', '~> 4.2.2'
  s.add_runtime_dependency 'pry', '~> 0.14.2'
  s.add_runtime_dependency 'pry-remote'
  s.add_runtime_dependency 'require_all', '~> 2.0.0'
end
