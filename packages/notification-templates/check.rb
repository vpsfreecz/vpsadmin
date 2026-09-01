# frozen_string_literal: true

require 'vpsadmin/api/notification_templates'

if ARGV.length != 1
  warn 'Usage: notification-template-check TEMPLATE_PATH'
  exit 2
end

begin
  directory = VpsAdmin::API::NotificationTemplates::Directory.new(ARGV.fetch(0))
  file_count = directory.templates.sum do |template|
    1 + template.variants.sum do |variant|
      %i[subject text html].count { |format| variant.content(format) }
    end
  end

  puts "Checked #{directory.templates.length} templates and #{file_count} template files"
rescue VpsAdmin::API::NotificationTemplates::InvalidTemplate => e
  warn e.message
  exit 1
end
