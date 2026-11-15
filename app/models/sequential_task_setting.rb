class SequentialTaskSetting < ActiveRecord::Base
  validates :bar_style, inclusion: { in: RedmineSequentialTasks::BarStyle::STYLES }

  belongs_to :tracker
  has_many :steps, -> { order(:position) }, class_name: 'SequentialTaskStep', foreign_key: 'sequential_task_setting_id', dependent: :destroy

  validates :tracker_id, presence: true, uniqueness: true
end
