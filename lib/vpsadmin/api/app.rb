module VpsAdmin
  module API
    class App < Sinatra::Base
      def self.init
        VpsAdmin.resources do |r|
          r.routes.each do |r|
            self.method(r.http_method).call(r.url) do
              action = r.action.new(params)
              action.exec
            end

            options r.url do
              desc = r.action.describe
              desc[:url] = r.url
              desc[:method] = r.http_method.to_s.upcase

              JSON.pretty_generate(desc)
            end
          end
        end
      end
    end
  end
end
