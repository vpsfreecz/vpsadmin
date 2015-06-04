require 'active_record'
require 'sinatra/activerecord/rake'
require './lib/vpsadmin'
require './lib/vpsadmin/api/tasks'

require 'rspec/core'
require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new(:spec) do |spec|
  spec.pattern = FileList['spec/**/*_spec.rb']
end
