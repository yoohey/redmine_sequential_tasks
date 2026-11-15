# frozen_string_literal: true

module RedmineSequentialTasks
  # Statistics of the time issues stay in a stage. Logic only.
  module StageStats
    MIN_SAMPLES = 3          # finished stays needed before there is a baseline
    SLOW_RATIO = 1.5         # "slower than usual": at least this many times the median ...
    SLOW_EXTRA_DAYS = 2      # ... and at least this many days more
    BOTTLENECK_RATIO = 1.2   # the median must be clearly longer than the standard days

    module_function

    def median(values)
      return nil if values.empty?

      sorted = values.sort
      mid = sorted.size / 2
      sorted.size.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0
    end

    def mean(values)
      values.empty? ? nil : values.sum.to_f / values.size
    end

    # Days of a stay: the block counts the working days from..to (inclusive); a stay is at least one day
    def dwell_days(from, to)
      [yield(from, to), 1].max
    end

    # visits - [{ dwell: days, plan: planned days or nil }] of finished stays
    # Returns count, mean, median and overrun_rate (the share of the stays that have a plan and took longer than it)
    def summarize(visits)
      dwells = visits.map { |v| v[:dwell] }
      planned = visits.reject { |v| v[:plan].nil? }
      { count: dwells.size, mean: mean(dwells), median: median(dwells),
        overrun_rate: planned.empty? ? nil : planned.count { |v| v[:dwell] > v[:plan] }.to_f / planned.size }
    end

    # The usual stay: the median of finished stays, when there are enough of them; else nil
    def baseline(dwells)
      return nil if dwells.size < MIN_SAMPLES

      { median: median(dwells), count: dwells.size }
    end

    # How many times the usual stay is the issue's stay so far (rounded to one decimal); nil unless it is clearly longer
    def slowness(elapsed, baseline)
      return nil if baseline.nil? || baseline[:median].to_f <= 0

      ratio = elapsed.to_f / baseline[:median]
      ratio >= SLOW_RATIO && elapsed - baseline[:median] >= SLOW_EXTRA_DAYS ? ratio.round(1) : nil
    end

    # stages - [{ key:, median:, standard:, count: }]; the key of the stage whose median is the longest compared with
    # its standard days (among those with enough stays and clearly longer), or nil
    def bottleneck(stages)
      candidates = stages.select do |s|
        s[:count] >= MIN_SAMPLES && s[:median] && s[:standard].to_f.positive? && s[:median].to_f / s[:standard] > BOTTLENECK_RATIO
      end
      candidates.max_by { |s| s[:median].to_f / s[:standard] }&.fetch(:key)
    end
  end
end
