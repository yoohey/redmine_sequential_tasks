# frozen_string_literal: true

# A stage of zero days: the first stage of a tracker may be a wait ("filed, but nobody has
# picked it up"). It has no bar of its own; the screens draw the time spent in it.
class AddZeroDayToIssueStages < ActiveRecord::Migration[7.2]
  def change
    add_column :issue_stages, :zero_day, :boolean, null: false, default: false
  end
end
