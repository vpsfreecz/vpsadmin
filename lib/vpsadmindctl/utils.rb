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

def unitize(v)
  return "#{v}M" if v < 1024

  bits = 19

  %w(T G).each_with_index do |u, i|
    n = 2 << (bits - 10*i)

    return "#{(v / n.to_f).round(1)}#{u}" if v >= n
  end

  "#{v}M"
end

def format_progress(t, progress)
  ret = case progress[:unit].to_sym
  when :mib
    "#{unitize(progress[:current])}/#{unitize(progress[:total])}"

  when :percent
    "#{progres[:current].to_f / progress[:total] * 100}%"

  else
    '?'
  end

  ret += '(?)' if t.to_i > (progress[:time] + 60)

  ret
end
