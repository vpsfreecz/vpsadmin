module VpsAdmin::ConsoleRouter
  class Server < Sinatra::Application
    configure do
      path = File.join(File.dirname(__FILE__), '..', '..', '..')
      
      set :protection, :except => :frame_options
      set :views, File.join(path, 'views')
      set :public_folder, File.join(path, 'public')
      set :router, Router.new
    end

    get '/console/:veid' do |veid|
      v = veid.to_i

      if settings.router.check_session(v, params[:session])
        erb :console, :locals => {:veid => v, :session => params[:session]}
      else
        "Access denied, invalid session"
      end
    end

    post '/console/feed/:veid' do |veid|
      v = veid.to_i

      if settings.router.check_session(v, params[:session])
        settings.router.send_cmd(v, params)

        {
            data: Base64.encode64(settings.router.get_console(v, params[:session])),
            session: true
        }.to_json

      else
        {data: "Access denied, invalid session", session: nil}.to_json
      end
    end
  end
end
