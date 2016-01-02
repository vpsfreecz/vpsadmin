require 'active_record'
require 'sinatra/activerecord/rake'
require 'rdoc/task'
require './lib/vpsadmin'
require './lib/vpsadmin/api/tasks'
require 'haveapi/tasks/hooks'

RDoc::Task.new do |rdoc|
  rdoc.rdoc_files.include('doc', 'lib', 'models')
  rdoc.options << '--line-numbers' << '--page-dir=doc'

  document_hooks(rdoc)
end
