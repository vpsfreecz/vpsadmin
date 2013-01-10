def format_duration(interval)
	h = interval / 3600 % 24
	m = interval / 60 % 60
	s = interval % 60
	"%02d:%02d:%02d" % [h, m, s]
end
