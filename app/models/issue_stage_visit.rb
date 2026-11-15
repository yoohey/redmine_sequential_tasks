class IssueStageVisit < ActiveRecord::Base
  belongs_to :issue_stage

  validates :entered_at, presence: true

  # Visits that have not been left yet
  scope :ongoing, -> { where(left_at: nil) }
end
