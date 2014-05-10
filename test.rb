require './lib/vpsadmin/vpsadmin'

#VpsAdmin::API.get_version(:all).each do |r|
#  #puts "Resource #{r}"
#  #r.actions do |a|
#  #  puts "\tAction #{a}: desc=#{a.desc}"
#  #end
#
#
#  r.routes.each do |r|
#    puts "#{r.http_method.to_s.upcase} #{r.url} - #{r.description}"
#  end
#end

api = VpsAdmin::API::Server.new
api.use_version([1, 2])
api.set_default_version(1)
api.mount('/')

#v1 = VpsAdmin::API.get_version(1)
#VpsAdmin::API.mount('/v1/', v1)

# VpsAdmin::API::App.routes.each do |http_method, routes|
#   routes.each do |route|
#     puts "#{http_method} #{route}"
#   end
# end
api.start!

