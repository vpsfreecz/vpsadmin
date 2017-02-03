require 'bundler/setup'
require 'active_record'
require 'sinatra/activerecord/rake'
require 'yard'
require './lib/vpsadmin'
require './lib/vpsadmin/api/tasks'
require 'haveapi/tasks/yard'

VpsAdmin::API::Plugin::Loader.load('api')

YARD::Rake::YardocTask.new do |t|
  t.files   = ['lib/**/*.rb', 'models/**/*.rb']
  t.options = ['--protected', '--markup=markdown', '--output-dir=html_doc', '--files=doc/*.md']
  t.before = Proc.new do
    document_hooks.call
    File.write(
        File.join('doc', 'Mail_templates.md'),
        ERB.new(File.read(File.join('doc', 'mail_templates.erb')), 0).result(binding)
    )
  end
end

task :log do
    ActiveRecord::Base.logger = Logger.new(STDOUT)
end
