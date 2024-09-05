lib = File.expand_path('lib', __dir__)
$:.unshift(lib) unless $:.include?(lib)
require 'vpsadmin/client/version'

Gem::Specification.new do |spec|
  spec.name          = 'vpsadmin-client'
  spec.version       = VpsAdmin::Client::VERSION
  spec.authors       = ['Jakub Skokan']
  spec.email         = ['jakub.skokan@vpsfree.cz']
  spec.summary       =
    spec.description = 'Ruby API and CLI for vpsAdmin API'
  spec.homepage      = ''
  spec.license       = 'GPL'

  spec.required_ruby_version = '>= 3.0'

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'curses'
  spec.add_dependency 'haveapi-client', '~> 0.23.6'
  spec.add_dependency 'json'
end
