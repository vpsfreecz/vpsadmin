# frozen_string_literal: true

require 'rake'

module PluginRakeTaskHelpers
  def with_rake_application
    old = Rake.application
    app = Rake::Application.new
    Rake.application = app
    yield app
  ensure
    Rake.application = old
  end

  def load_plugin_rake_tasks(*relative_paths)
    relative_paths.each do |path|
      load plugin_rake_task_path(path)
    end
  end

  def plugin_rake_task_path(path)
    [
      File.expand_path("../../../#{path}", __dir__),
      File.expand_path("../../#{path}", __dir__)
    ].find { |candidate| File.exist?(candidate) } || File.expand_path("../../../#{path}", __dir__)
  end

  def invoke_rake_task(name, env: {})
    with_env(env) do
      task = Rake::Task[name]
      task.reenable
      task.invoke
    end
  end
end

RSpec.configure do |config|
  config.include PluginRakeTaskHelpers
end
