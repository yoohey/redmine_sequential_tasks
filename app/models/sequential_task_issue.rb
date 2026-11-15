class SequentialTaskIssue < ActiveRecord::Base
  belongs_to :issue
  belongs_to :branched_from_issue, class_name: 'Issue', foreign_key: 'branched_from_issue_id', optional: true

  validates :issue_id, presence: true, uniqueness: true
end
