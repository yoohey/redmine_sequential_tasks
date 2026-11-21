class SequentialTaskIssue < ActiveRecord::Base
  belongs_to :issue
  belongs_to :branched_from_issue, class_name: 'Issue', foreign_key: 'branched_from_issue_id', optional: true

  validates :issue_id, presence: true, uniqueness: true

  # The start date a new branched task gets when none is given: today, or the parent's start date when the parent
  # starts later (a branch of a task that begins next week begins with it, not before it).
  def self.default_start_date(parent, today = User.current.today)
    [today, parent.start_date].compact.max
  end
end
