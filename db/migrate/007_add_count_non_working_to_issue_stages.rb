# frozen_string_literal: true

# A stage that counts the non-working days too: set per issue on "adjust the schedule",
# e.g. a stage that was recovered by working on the weekend. Off = working days only (Redmine's non-working week days).
class AddCountNonWorkingToIssueStages < ActiveRecord::Migration[7.2]
  def change
    add_column :issue_stages, :count_non_working, :boolean, null: false, default: false
  end
end
