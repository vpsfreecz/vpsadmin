lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'nodectl/version'

Gem::Specification.new do |s|
  s.name        = 'nodectl'

  if ENV['VPSADMIN_BUILD_ID']
    s.version   = "#{NodeCtl::VERSION}.build#{ENV['VPSADMIN_BUILD_ID']}"
  else
    s.version   = NodeCtl::VERSION
  end

  s.summary     =
  s.description = 'CLI for nodectld'
  s.authors     = 'Jakub Skokan'
  s.email       = 'jakub.skokan@vpsfree.cz'
  s.files       = `git ls-files -z`.split("\x0")
  s.executables = s.files.grep(%r{^bin/}) { |f| File.basename(f) }
  s.license     = 'GPL'

  s.required_ruby_version = '>= 2.0.0'

  s.add_runtime_dependency 'json'
  s.add_runtime_dependency 'libnodectld', s.version
  s.add_runtime_dependency 'pry-remote'
  s.add_runtime_dependency 'require_all', '~> 2.0.0'
end
