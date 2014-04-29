require 'require_all'
require 'active_record'
require 'paper_trail'
require 'sinatra/base'

require_rel '../../models'
require_rel 'api'

module VpsAdmin
  def resources
    API::Resources.constants.select do |c|
      obj = API::Resources.const_get(c)

      if obj.obj_type == :resource
        yield obj
      end
    end
  end

  module_function :resources

  API::App.init
end
