# Migration for sequential task tables: settings, steps, issue metadata, and stages
class CreateSequentialTaskTables < ActiveRecord::Migration[7.2]
  def change
    # Tracker settings for enabling sequential task management
    create_table :sequential_task_settings do |t|
      t.integer :tracker_id, null: false, index: { unique: true }
      t.boolean :enabled, default: true, null: false
      t.timestamps
    end

    # Stage steps definition per tracker setting (status, order, default days, color)
    create_table :sequential_task_steps do |t|
      t.integer :sequential_task_setting_id, null: false
      t.integer :status_id, null: false
      t.integer :position, default: 1, null: false
      t.integer :default_duration_days, default: 1, null: false
      t.string :color, default: '#3498db'
      t.timestamps
    end
    add_index :sequential_task_steps, [:sequential_task_setting_id, :position], name: 'idx_seq_task_steps_setting_pos'
    add_index :sequential_task_steps, [:sequential_task_setting_id, :status_id], name: 'idx_seq_task_steps_setting_status'

    # Issue-level metadata for custom ordering and loose branching
    create_table :sequential_task_issues do |t|
      t.integer :issue_id, null: false, index: { unique: true }
      t.integer :branched_from_issue_id, index: true
      t.integer :position, default: 1, null: false
      t.timestamps
    end

    # Scheduled vs actual timeline per stage for each issue
    create_table :issue_stages do |t|
      t.integer :issue_id, null: false
      t.integer :status_id, null: false
      t.integer :position, default: 1, null: false
      t.date :planned_start_date
      t.date :planned_end_date
      t.datetime :actual_start_at
      t.datetime :actual_end_at
      t.string :stage_status, default: 'pending', null: false
      t.timestamps
    end
    add_index :issue_stages, [:issue_id, :position]
    add_index :issue_stages, [:issue_id, :status_id]
  end
end
