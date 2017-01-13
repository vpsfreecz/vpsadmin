require 'bundler/setup'
require 'active_record'
require 'sinatra/activerecord/rake'
require 'yard'
require './lib/vpsadmin'
require './lib/vpsadmin/api/tasks'
require 'haveapi/tasks/yard'

VpsAdmin::API::Plugin::Loader.load

YARD::Rake::YardocTask.new do |t|
  t.files   = ['lib/**/*.rb', 'models/**/*.rb']
  t.options = ['--protected', '--output-dir=html_doc', '--files=doc/*.md']
  t.before = document_hooks
end

task :log do
    ActiveRecord::Base.logger = Logger.new(STDOUT)
end
