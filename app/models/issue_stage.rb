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

  # Returns true if currently in progress and past the planned end date
  def delayed?
    stage_status == 'in_progress' && planned_end_date.present? && User.current.today > planned_end_date
  end

  # Returns the number of days delayed past the planned end date
  def delay_days
    delayed? ? (User.current.today - planned_end_date).to_i : 0
  end
end
