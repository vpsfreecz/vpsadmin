require './lib/vpsadmin/vpsadmin'

VpsAdmin.resources do |r|
  puts "Resource #{r}"
  r.actions do |a|
    puts "\tAction #{a}: desc=#{a.desc}"
  end


  r.routes.each do |r|
    puts "#{r.http_method.to_s.upcase} #{r.url} - #{r.description}"
  end
end

VpsAdmin::API::App.run!
