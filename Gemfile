source 'https://rubygems.org'

gem 'haveapi', '~> 0.9.0'
gem 'activerecord', '~> 4.1.14'
gem 'sinatra-activerecord', '~> 2.0.11'
gem 'paper_trail', '~> 3.0.9'
gem 'require_all'
gem 'rake'
gem 'composite_primary_keys', '~> 7.0.10'
gem 'eventmachine'
gem 'ancestry', '~> 2.1.0'
gem 'mysql2', '~> 0.3.13'
gem 'bcrypt', '~> 3.1.10'
gem 'ipaddress', '~> 0.8.0'
gem 'activerecord-mysql-unsigned'

group :test do
  gem 'rspec'
end

group :development do
  gem 'pry'
  gem 'yard'
end

Dir.entries('plugins').select do |v|
  next if v == '.' || v == '..'
  
  path = File.join('plugins', v, 'api', 'Gemfile')
  next unless File.exists?(path)

  eval_gemfile path
end
