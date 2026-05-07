module VpsAdmin::ConsoleRouter
  class Server < Sinatra::Application
    class RouterFactory
      def call
        Router.new
      end
    end

    configure do
      path = File.join(__dir__, '..', '..', '..')

      set :protection, except: :frame_options
      set :views, File.join(path, 'views')
      set :public_folder, File.join(path, 'public')
      set :router, nil
      set :router_factory, RouterFactory.new
    end

    helpers do
      def router
        return settings.router if settings.router

        settings.set(:router, settings.router_factory.call)
        settings.router
      end
    end

    get '/console/:vps_id' do |vps_id_str|
      vps_id = vps_id_str.to_i

      if router.check_session(vps_id, params[:session])
        erb :console, locals: {
          api_url: router.api_url,
          vps_id:,
          auth_type: params[:auth_type],
          auth_token: params[:auth_token],
          session: params[:session]
        }
      else
        'Access denied, invalid session'
      end
    end

    post '/console/feed/:vps_id' do |vps_id_str|
      data = router.read_write_console(
        vps_id_str.to_i,
        params[:session],
        params[:keys],
        params[:width].to_i,
        params[:height].to_i
      )

      if data
        {
          data: Base64.encode64(data),
          session: true
        }.to_json
      else
        { data: 'Access denied, invalid session', session: nil }.to_json
      end
    end
  end
end
