module VpsAdmin::ConsoleRouter
  class Server < Sinatra::Application
    configure do
      path = File.join(__dir__, '..', '..', '..')

      set :protection, except: :frame_options
      set :views, File.join(path, 'views')
      set :public_folder, File.join(path, 'public')
      set :router, Router.new
    end

    get '/console/:vps_id' do |vps_id_str|
      vps_id = vps_id_str.to_i

      if settings.router.check_session(vps_id, params[:session])
        erb :console, locals: {
          api_url: settings.router.api_url,
          vps_id: vps_id,
          auth_type: params[:auth_type],
          auth_token: params[:auth_token],
          session: params[:session]
        }
      else
        'Access denied, invalid session'
      end
    end

    post '/console/feed/:vps_id' do |vps_id_str|
      data = settings.router.read_write_console(
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
