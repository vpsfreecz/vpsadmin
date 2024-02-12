lib = File.expand_path('lib', __dir__)
$:.unshift(lib) unless $:.include?(lib)
require 'nodectl/version'

Gem::Specification.new do |s|
  s.name = 'nodectl'

  s.version = if ENV['VPSADMIN_BUILD_ID']
                "#{NodeCtl::VERSION}.build#{ENV['VPSADMIN_BUILD_ID']}"
              else
                NodeCtl::VERSION
              end

  s.summary     =
    s.description = 'CLI for nodectld'
  s.authors     = 'Jakub Skokan'
  s.email       = 'jakub.skokan@vpsfree.cz'
  s.files       = `git ls-files -z`.split("\x0")
  s.files      += Dir['man/man?/*.?']
  s.executables = s.files.grep(%r{^bin/}) { |f| File.basename(f) }
  s.license     = 'GPL'

  s.required_ruby_version = '>= 3.2.0'

  s.add_runtime_dependency 'json'
  s.add_runtime_dependency 'libnodectld', s.version
  s.add_runtime_dependency 'libosctl', ENV['OS_BUILD_ID']
  s.add_runtime_dependency 'pry', '~> 0.14.2'
  s.add_runtime_dependency 'pry-remote'
  s.add_runtime_dependency 'require_all', '~> 2.0.0'
  s.add_development_dependency 'md2man'
  s.add_development_dependency 'rake'
end
