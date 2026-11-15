# frozen_string_literal: true

module RedmineSequentialTasks
  # The standard days of a stage in a project: what the project sets for itself, else the tracker's.
  # The project's overrides are read once.
  class StandardDays
    def initialize(project_id)
      @overrides = SequentialTaskProjectStep.where(project_id: project_id)
                                            .pluck(:tracker_id, :status_id, :default_duration_days)
                                            .to_h { |tracker_id, status_id, days| [[tracker_id, status_id], days] }
    end

    # step - a SequentialTaskStep of the setting of the tracker
    def days(tracker_id, step)
      @overrides[[tracker_id, step.status_id]] || step.default_duration_days
    end

    def overridden?(tracker_id, status_id)
      @overrides.key?([tracker_id, status_id])
    end
  end
end
