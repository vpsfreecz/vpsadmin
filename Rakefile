require_relative 'lib/vpsadmin/mail-templates'

desc 'Install mail templates'
task :install do
  VpsAdmin::MailTemplates.install(
      ENV['API'] || 'https://api.vpsfree.cz',
      ENV['VERSION'] || '2.0',
      ENV['USERNAME'],
      ENV['PASSWORD'],
  )
end

task default: [:install]
