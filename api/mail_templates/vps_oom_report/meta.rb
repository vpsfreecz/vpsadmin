template :vps_oom_report do
  label 'VPS OOM report'

  lang :en do
    subject '[vpsAdmin] VPS <%= @vps.hostname %> had out-of-memory events'
  end
end
