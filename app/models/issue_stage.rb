class IssueStage < ActiveRecord::Base
  STAGE_STATUSES = %w[pending in_progress completed skipped].freeze

  belongs_to :issue
  belongs_to :status, class_name: 'IssueStatus', foreign_key: 'status_id'
  has_many :visits, class_name: 'IssueStageVisit', foreign_key: 'issue_stage_id', dependent: :destroy

  validates :status_id, presence: true, uniqueness: { scope: :issue_id }
  validates :stage_status, inclusion: { in: STAGE_STATUSES }

  # Does the stage count the non-working days too? (A stage loaded without the column counts working days)
  def all_days?
    has_attribute?(:count_non_working) && count_non_working ? true : false
  end
end
