lib = File.expand_path('../libnodectld/lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'nodectld/version'

Gem::Specification.new do |s|
  s.name = 'nodectld'

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

  s.required_ruby_version = '>= 3.1.0'

  s.add_runtime_dependency 'libnodectld', s.version
  s.add_development_dependency 'rake'
end
