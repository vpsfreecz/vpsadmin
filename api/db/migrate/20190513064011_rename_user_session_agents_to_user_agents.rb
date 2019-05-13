class RenameUserSessionAgentsToUserAgents < ActiveRecord::Migration
  def change
    rename_table :user_session_agents, :user_agents
    rename_index :user_agents, :user_session_agents_hash, :user_agents_hash
    rename_column :user_sessions, :user_session_agent_id, :user_agent_id
  end
end
