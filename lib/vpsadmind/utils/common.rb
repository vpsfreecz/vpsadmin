def log_time
  Time.new.strftime("%Y-%m-%d %H:%M:%S")
end

def log(msg)
  puts "[#{log_time}] #{msg}"
end
