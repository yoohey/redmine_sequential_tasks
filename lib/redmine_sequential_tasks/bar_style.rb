# frozen_string_literal: true

module RedmineSequentialTasks
  # How the stage bars look on the timeline; each tracker has its own (column bar_style of its setting):
  #   bold   - filled with the stage color, white text (the first look)
  #   subtle - a pale fill with an edge in the stage color, dark text
  #   light  - a nearly white chip with a gray border and an edge in the stage color
  module BarStyle
    STYLES = %w[bold subtle light].freeze
    DEFAULT = 'bold'

    module_function

    # The value if it is a known style, else the default
    def normalize(value)
      STYLES.include?(value.to_s) ? value.to_s : DEFAULT
    end
  end
end
