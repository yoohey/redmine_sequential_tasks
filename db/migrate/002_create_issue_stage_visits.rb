# Visit history per stage: one row each time an issue enters a stage
class CreateIssueStageVisits < ActiveRecord::Migration[7.2]
  def up
    create_table :issue_stage_visits do |t|
      t.integer :issue_stage_id, null: false, index: true
      t.datetime :entered_at, null: false
      t.datetime :left_at
      t.timestamps
    end

    # Existing data: every stage that was entered becomes its first visit.
    # A stage that is not in progress but has no end (it was rolled back from) is closed at its last update.
    execute <<~SQL
      INSERT INTO issue_stage_visits (issue_stage_id, entered_at, left_at, created_at, updated_at)
      SELECT id,
             actual_start_at,
             CASE WHEN stage_status = 'in_progress' THEN actual_end_at
                  ELSE COALESCE(actual_end_at, updated_at) END,
             CURRENT_TIMESTAMP,
             CURRENT_TIMESTAMP
        FROM issue_stages
       WHERE actual_start_at IS NOT NULL
    SQL
  end

  def down
    drop_table :issue_stage_visits
  end
end
