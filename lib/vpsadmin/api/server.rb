class VpsAdmin::API::Server
  module ServerHelpers
    def authenticate!
      unless authenticated?
        report_error(401, {'WWW-Authenticate' => 'Basic realm="Restricted Area"'},
                     'Action requires user to authenticate')
      end
    end

    def authenticated?
      return @current_user if @current_user

      auth = Rack::Auth::Basic::Request.new(request.env)
      if auth.provided? && auth.basic? && auth.credentials
          @current_user = User.authenticate(*auth.credentials)
      end

      User.current = @current_user

      @current_user
    end

    def current_user
      @current_user
    end

    def pretty_format(obj)
      ret = ''
      PP.pp(obj, ret)
    end

    def report_error(code, headers, msg)
      halt code, headers, JSON.pretty_generate({
                                                   status: false,
                                                   response: nil,
                                                   message: msg
                                               })
    end
  end

  # Include specific version +v+ of API.
  # +v+ can be one of:
  # [:all]     use all available versions
  # [Array]    use all versions in +Array+
  # [version]  include only concrete version
  # +default+ is set only when including concrete version. Use
  # set_default_version otherwise.
  def use_version(v, default: false)
    @versions ||= []

    if v == :all
      @versions = VpsAdmin::API.get_versions
    elsif v.is_a?(Array)
      @versions += v
      @versions.uniq!
    else
      @versions << v
      @default_version = v if default
    end
  end

  # Set default version of API.
  def set_default_version(v)
    @default_version = v
  end

  # Load routes for all resource from included API versions.
  # All routes are mounted under prefix +path+.
  # If no default version is set, the last included version is used.
  def mount(prefix='/')
    @root = prefix

    @sinatra = Sinatra.new do
      set :views, settings.root + '/views'
      set :public_folder, settings.root + '/public'
      set :bind, '0.0.0.0'

      # This must be called before registering paper trail, or else it will
      # not be logging current user.
      before do
        authenticated?
      end

      register PaperTrail::Sinatra

      helpers ServerHelpers

      not_found do
        report_error(404, {}, 'Action not found')
      end

      after do
        ActiveRecord::Base.clear_active_connections!
      end
    end

    @sinatra.set(:api_server, self)

    @routes = {}

    # Mount root
    @sinatra.get @root do
      @api = settings.api_server.describe
      erb :index, layout: :main
    end

    @sinatra.options @root do
      JSON.pretty_generate(settings.api_server.describe)
    end

    @default_version ||= @versions.last

    # Mount default version first
    mount_version(@root, @default_version)

    @versions.each do |v|
      mount_version(version_prefix(v), v)
    end
  end

  def mount_version(prefix, v)
    @routes[v] = {}

    @sinatra.get prefix do
      @v = v
      @help = settings.api_server.describe_version(v)
      erb :version, layout: :main
    end

    @sinatra.options prefix do
      JSON.pretty_generate(settings.api_server.describe_version(v))
    end

    VpsAdmin::API.get_version_resources(v).each do |resource|
      @routes[v][resource] = {resources: {}, actions: {}}

      resource.routes(prefix).each do |route|
        if route.is_a?(Hash)
          @routes[v][resource][:resources][route.keys.first] = mount_nested_resource(v, route.values.first)

        else
          @routes[v][resource][:actions][route.action] = route.url
          mount_action(v, route)
        end
      end
    end
  end

  def mount_nested_resource(v, routes)
    ret = {resources: {}, actions: {}}

    routes.each do |route|
      if route.is_a?(Hash)
        ret[:resources][route.keys.first] = mount_nested_resource(v, route.values.first)

      else
        ret[:actions][route.action] = route.url
        mount_action(v, route)
      end
    end

    ret
  end

  def mount_action(v, route)
    @sinatra.method(route.http_method).call(route.url) do
      authenticate! if route.action.auth

      request.body.rewind

      begin
        body = request.body.read

        if body.empty?
          body = nil
        else
          body = JSON.parse(body, symbolize_names: true)
        end

      rescue => e
        report_error(400, {}, 'Bad JSON syntax')
      end

      action = route.action.new(v, params, body)

      unless action.authorized?(current_user)
        report_error(403, {}, 'Access denied. Insufficient permissions.')
      end

      status, reply, errors = action.safe_exec
      reply = {
          status: status,
          response: status ? reply : nil,
          message: !status ? reply : nil,
          errors: errors
      }

      JSON.pretty_generate(reply)
    end

    @sinatra.options route.url do
      route_method = route.http_method.to_s.upcase

      pass if params[:method] && params[:method] != route_method

      desc = route.action.describe
      desc[:url] = route.url
      desc[:method] = route_method
      desc[:help] = "#{route.url}?method=#{route_method}"

      JSON.pretty_generate(desc)
    end
  end

  def describe
    ret = {
        default_version: @default_version,
        versions: {default: describe_version(@default_version)},
    }

    @versions.each do |v|
      ret[:versions][v] = describe_version(v)
    end

    ret
  end

  def describe_version(v)
    ret = {resources: {}, help: version_prefix(v)}

    #puts JSON.pretty_generate(@routes)

    @routes[v].each do |resource, children|
      r_name = resource.to_s.demodulize.underscore

      ret[:resources][r_name] = describe_resource(resource, children)
    end

    ret
  end

  def describe_resource(r, hash)
    ret = {description: r.desc, actions: {}, resources: {}}

    hash[:actions].each do |action, url|
      a_name = action.to_s.demodulize.underscore
      route_method = action.http_method.to_s.upcase

      ret[:actions][a_name] = action.describe
      ret[:actions][a_name].update({
                                       url: url,
                                       method: route_method,
                                       help: "#{url}?method=#{route_method}"
                                   })
    end

    hash[:resources].each do |resource, children|
      ret[:resources][resource.to_s.demodulize.underscore] = describe_resource(resource, children)
    end

    ret
  end

  def version_prefix(v)
    "#{@root}v#{v}/"
  end

  def app
    @sinatra
  end

  def start!
    @sinatra.run!
  end
end

