def format_duration(interval)
  d = interval / 86400
  h = interval / 3600 % 24
  m = interval / 60 % 60
  s = interval % 60

  if d > 0
    "%d days, %02d:%02d:%02d" % [d, h, m, s]
  else
    "%02d:%02d:%02d" % [h, m, s]
  end
end
