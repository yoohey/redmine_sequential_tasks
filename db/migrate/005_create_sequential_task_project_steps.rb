# frozen_string_literal: true

# Standard days that a project overrides: one row per project, tracker and status. A status
# without a row uses the days of the tracker setting.
class CreateSequentialTaskProjectSteps < ActiveRecord::Migration[7.2]
  def change
    create_table :sequential_task_project_steps do |t|
      t.integer :project_id, null: false
      t.integer :tracker_id, null: false
      t.integer :status_id, null: false
      t.integer :default_duration_days, null: false
      t.timestamps
    end
    add_index :sequential_task_project_steps, [:project_id, :tracker_id, :status_id], unique: true, name: 'idx_seq_task_project_steps'
  end
end
