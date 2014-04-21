require 'lib/executor'

class Dummy < Executor
  def dummy
    sleep(6000)
  end

  def dummy2
    nil
  end

  def dummydummydummy
    dummy
  end
end
