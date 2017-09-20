class ForgetUserPasswords < ActiveRecord::Migration
  def up
    ActiveRecord::Base.connection.execute(
        "UPDATE users SET password = '!' WHERE object_state = 3"
    )
  end
end
