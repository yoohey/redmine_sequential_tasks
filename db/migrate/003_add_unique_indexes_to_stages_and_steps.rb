# One stage per status and issue, one step per status and tracker setting (review A-14).
# The old indexes on the same columns were not unique; they are replaced.
# Fails if duplicate rows exist: remove them first.
class AddUniqueIndexesToStagesAndSteps < ActiveRecord::Migration[7.2]
  def up
    remove_index :issue_stages, column: [:issue_id, :status_id]
    add_index :issue_stages, [:issue_id, :status_id], unique: true

    remove_index :sequential_task_steps, name: 'idx_seq_task_steps_setting_status'
    add_index :sequential_task_steps, [:sequential_task_setting_id, :status_id],
              unique: true, name: 'idx_seq_task_steps_setting_status'
  end

  def down
    remove_index :sequential_task_steps, name: 'idx_seq_task_steps_setting_status'
    add_index :sequential_task_steps, [:sequential_task_setting_id, :status_id], name: 'idx_seq_task_steps_setting_status'

    remove_index :issue_stages, column: [:issue_id, :status_id]
    add_index :issue_stages, [:issue_id, :status_id]
  end
end
