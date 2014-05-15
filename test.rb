require './lib/vpsadmin/vpsadmin'

api = HaveAPI::Server.new(VpsAdmin::API::Resources)
api.use_version([1, 2])
api.set_default_version(1)
api.mount('/')

api.start!
