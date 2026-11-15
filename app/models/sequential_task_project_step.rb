# frozen_string_literal: true

# The standard days of a status that a project sets for itself, instead of those of the tracker setting
class SequentialTaskProjectStep < ActiveRecord::Base
  belongs_to :project

  validates :project_id, :tracker_id, :status_id, presence: true
  validates :default_duration_days, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 365 }
  validates :status_id, uniqueness: { scope: [:project_id, :tracker_id] }
end
