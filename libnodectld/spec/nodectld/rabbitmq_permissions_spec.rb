require 'open3'
require 'rbconfig'
require_relative '../../../tools/rabbitmqcfg'

RSpec.describe Cli do
  def permissions_for(type, user)
    script = File.expand_path('../../../tools/rabbitmqcfg.rb', __dir__)
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      script,
      'user',
      '--perms',
      type,
      user
    )

    expect(status).to be_success, stderr

    stdout.scan(/"([^"]+)"/).flatten.map { |pattern| Regexp.new(pattern) }
  end

  def notification_resources
    [
      'vpsadmin.notifications',
      'vpsadmin.notifications.email',
      'vpsadmin.notifications.telegram',
      'vpsadmin.notifications.sms',
      'vpsadmin.notifications.webhook',
      'vpsadmin.notifications.grouping'
    ]
  end

  it 'allows the console router to declare and publish to control exchanges' do
    configure, write, = permissions_for('console', 'console')

    expect(configure).to match('console:node1.example.test:control')
    expect(write).to match('console:node1.example.test:control')
  end

  it 'allows the API to declare, bind and publish notification resources' do
    configure, write, read = permissions_for('api', 'api')

    notification_resources.each do |resource|
      expect(configure).to match(resource)
      expect(write).to match(resource)
    end

    expect(read).to match('vpsadmin.notifications')
  end

  it 'does not allow the API to consume notification queues' do
    _configure, _write, read = permissions_for('api', 'api')

    notification_resources.drop(1).each do |queue|
      expect(read).not_to match(queue)
    end

    expect(read).not_to match('amq.gen-api')
    expect(read).not_to match('vpsadmin.notifications.unrelated')
  end

  it 'does not allow the API to configure or publish unrelated resources' do
    configure, write, = permissions_for('api', 'api')

    [
      'amq.gen-api',
      'unrelated.exchange',
      'unrelated.queue',
      'vpsadmin.notifications.email.extra'
    ].each do |resource|
      expect(configure).not_to match(resource)
      expect(write).not_to match(resource)
    end
  end

  it 'allows nodes to bind and read their own control queue' do
    _configure, _write, read = permissions_for('node', 'node1.example.test')

    expect(read).to match('console:node1.example.test:control')
    expect(read).not_to match('console:node2.example.test:control')
  end
end
