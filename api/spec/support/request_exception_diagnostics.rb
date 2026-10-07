# frozen_string_literal: true

require 'json'
require 'haveapi/hooks'

module RequestExceptionDiagnostics
  ROOT = File.expand_path('../../..', __dir__).freeze
  PREFIX = 'API_REQUEST_EXCEPTION_DIAGNOSTICS '
  STATE_KEY = :request_exception_diagnostics
  THREAD_KEY = :vpsadmin_spec_request_exception_scope
  MAX_EVENTS = 8
  MAX_BYTES = 16 * 1024
  METHODS = %w[GET HEAD POST PUT PATCH DELETE OPTIONS TRACE CONNECT].freeze
  Scope = Struct.new(:example, :env, :ordinal, :events)

  class App
    def initialize(app)
      @app = app
    end

    def call(env)
      RequestExceptionDiagnostics.with_request(env) { @app.call(env) }
    end
  end

  module Dispatcher
    def call_for(*arguments, **keywords, &)
      # Only observation is rescued; delegation retains its original behavior.
      begin
        RequestExceptionDiagnostics.capture(arguments, keywords)
      rescue StandardError
        RequestExceptionDiagnostics.observation_error
      end
      super
    end
  end

  class Listener
    def initialize(reporter)
      @reporter = reporter
    end

    def example_failed(notification)
      packet = RequestExceptionDiagnostics.take(notification.example)
      @reporter.message("#{PREFIX}#{JSON.generate(packet)}") if packet
    rescue StandardError
      # Diagnostic reporting must never replace the actual example failure.
      begin
        @reporter.message("#{PREFIX}{\"format\":1,\"observation_error\":true}")
      rescue StandardError
        nil
      end
    end

    def example_passed(notification)
      RequestExceptionDiagnostics.discard(notification.example)
    end

    alias example_pending example_passed
  end

  class << self
    def install!
      return if @installed

      HaveAPI::Hooks.singleton_class.prepend(Dispatcher)
      reporter = RSpec.configuration.reporter
      reporter.register_listener(Listener.new(reporter), :example_failed, :example_passed, :example_pending)
      @installed = true
    end

    def with_request(env)
      previous = Thread.current.thread_variable_get(THREAD_KEY)
      scope = prepare_scope(env)
      Thread.current.thread_variable_set(THREAD_KEY, scope)
      begin
        result = yield
        finish_scope(scope, result)
        result
      ensure
        Thread.current.thread_variable_set(THREAD_KEY, previous)
      end
    end

    def prepare_scope(env)
      example = RSpec.current_example
      return unless example

      state = state_for(example)
      state[:ordinal] += 1
      Scope.new(example, env, state[:ordinal], [])
    rescue StandardError
      observation_error
      nil
    end

    def finish_scope(scope, result)
      return unless scope

      status = result.is_a?(Array) && result[0]
      status = 'unavailable' unless status.is_a?(Integer) && status.between?(100, 599)
      scope.events.each { |event| event['http_status'] = status }
    rescue StandardError
      observation_error
    end

    def capture(arguments, keywords)
      name = arguments[1]
      return unless %i[exec_exception request_exception].include?(name)

      scope = Thread.current.thread_variable_get(THREAD_KEY)
      return unless scope && RSpec.current_example.equal?(scope.example)

      args = keywords[:args]
      unless args.is_a?(Array) && args.length >= 2
        observation_error
        return
      end

      context, exception = args
      unless defined?(HaveAPI::Context) && context.is_a?(HaveAPI::Context)
        observation_error
        return
      end
      return unless context.request && context.request.env.equal?(scope.env)
      return unless exception.is_a?(Exception)

      method = scope.env['REQUEST_METHOD']
      event = {
        'request' => scope.ordinal,
        'method' => method.is_a?(String) && METHODS.include?(method) ? method.dup.freeze : 'unknown',
        'http_status' => 'unavailable',
        'dispatcher' => name.to_s,
        'exceptions' => project_exception(exception)
      }
      state = state_for(scope.example)
      candidate = state[:packet].merge('events' => state[:packet]['events'] + [event])
      if state[:packet]['events'].length >= MAX_EVENTS || PREFIX.bytesize + JSON.generate(candidate).bytesize > MAX_BYTES
        state[:packet]['truncated'] = true
        return
      end

      state[:packet]['events'] << event
      scope.events << event
    end

    def observation_error
      scope = Thread.current.thread_variable_get(THREAD_KEY)
      return unless scope && RSpec.current_example.equal?(scope.example)

      state_for(scope.example)[:packet]['observation_error'] = true
    rescue StandardError
      nil
    end

    def state_for(example)
      example.metadata[STATE_KEY] ||= {
        ordinal: 0,
        packet: {
          'format' => 1,
          'example' => example_id(example),
          'events' => [],
          'truncated' => false,
          'observation_error' => false
        }
      }
    end

    def example_id(example)
      id = example.id
      return 'unavailable' unless id.is_a?(String) && id.bytesize <= 512

      match = %r{\A(?:\./)?(spec/(?:[A-Za-z0-9_.-]+/)*[A-Za-z0-9_.-]+_spec\.rb)(\[\d+(?::\d+)*\])\z}.match(id)
      return 'unavailable' unless match
      return 'unavailable' unless public_sources.has_key?(File.join(ROOT, 'api', match[1]))

      "api/#{match[1]}#{match[2]}"
    rescue StandardError
      'unavailable'
    end

    def project_exception(exception)
      seen = []
      objects = []
      current = exception
      3.times do
        break unless current.is_a?(Exception)

        if seen.any? { |item| item.equal?(current) }
          objects.last['cause_cycle'] = true
          break
        end
        seen << current
        name = current.class.name
        name = 'unavailable' unless name.is_a?(String) && name.bytesize <= 192 &&
                                    /\A[A-Z]\w*(?:::[A-Z]\w*)*\z/.match?(name)
        locations = current.backtrace_locations
        frames = []
        if locations.is_a?(Array)
          locations.first(64).each do |location|
            path = location.absolute_path || location.path
            id = public_sources[path]
            line = location.lineno
            next unless id && line.is_a?(Integer) && line.between?(1, 2_147_483_647)

            frames << { 'source_id' => id, 'line' => line }
            break if frames.length == 6
          end
        end
        trace =
          if locations.is_a?(Array)
            locations.length > 64 || frames.length == 6 ? 'bounded' : 'available'
          else
            'unavailable'
          end
        objects << {
          'class' => name.dup.freeze,
          'frames' => frames,
          'trace' => trace
        }
        current = current.cause
      end
      objects.last['causes_truncated'] = true if objects.length == 3 && current.is_a?(Exception)
      objects
    end

    def public_sources
      @public_sources ||= begin
        sources = {}
        patterns = ['api/{lib,models,spec}/**/*.rb', 'plugins/*/api/{lib,models,spec}/**/*.rb']
        patterns.each do |pattern|
          Dir.glob(File.join(ROOT, pattern)).each do |path|
            add_source(sources, path, path.delete_prefix("#{ROOT}/"))
          end
        end
        Gem.loaded_specs.each_value do |spec|
          prefix = "#{spec.name}/#{spec.version}/lib/"
          lib = File.join(spec.full_gem_path, 'lib')
          Dir.glob(File.join(lib, '**/*.rb')).each do |path|
            add_source(sources, path, prefix + path.delete_prefix("#{lib}/"))
          end
        end
        sources.freeze
      end
    end

    def add_source(sources, path, id)
      return unless File.file?(path) && !File.symlink?(path)
      return unless id.bytesize <= 256 && %r{\A[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)+\.rb\z}.match?(id)

      sources[path] = id.freeze
    end

    def take(example)
      state = example.metadata.delete(STATE_KEY)
      return unless state && (state[:packet]['events'].any? || state[:packet]['observation_error'] || state[:packet]['truncated'])

      state[:packet]
    end

    def discard(example)
      example.metadata.delete(STATE_KEY)
      nil
    end
  end
end

RequestExceptionDiagnostics.install!
