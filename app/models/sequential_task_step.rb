class SequentialTaskStep < ActiveRecord::Base
  belongs_to :sequential_task_setting
  belongs_to :status, class_name: 'IssueStatus', foreign_key: 'status_id'

  # Sample colors offered on the settings screen (the default first). Spread over the hues and kept away from the
  # delay red (#ef4444) so a stage is never mistaken for a delayed one. Dark enough for the white text of the bold bars.
  PALETTE = %w[#3498db #0284c7 #0d9488 #16a34a #65a30d #ca8a04 #ea580c #ec4899 #a855f7 #6366f1 #78716c #64748b].freeze

  COLOR_FORMAT = /\A#\h{6}\z/
  DEFAULT_COLOR = '#3498db'

  validates :color, format: { with: COLOR_FORMAT }, allow_blank: true
  validates :status_id, presence: true, uniqueness: { scope: :sequential_task_setting_id }
  validates :default_duration_days, numericality: { greater_than_or_equal_to: 0 }
end
