# frozen_string_literal: true

# == Schema Information
#
# Table name: syncs
#
#  id                :bigint           not null, primary key
#  workspace_id      :integer
#  source_id         :integer
#  model_id          :integer
#  destination_id    :integer
#  configuration     :jsonb
#  source_catalog_id :integer
#  schedule_type     :string
#  sync_interval     :integer
#  sync_interval_unit:string
#  cron_expression   :string
#  status            :integer
#  cursor_field      :string
#  current_cursor_field :string
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#
class Sync < ApplicationRecord
  include AASM
  include Discard::Model

  validates :workspace_id, presence: true
  validates :source_id, presence: true
  validates :destination_id, presence: true
  validates :model_id, presence: true
  validates :configuration, presence: true
  validates :schedule_type, presence: true
  validates :sync_interval, presence: true, numericality: { greater_than: 0 }, if: :interval?
  validates :sync_interval_unit, presence: true, if: :interval?
  validates :cron_expression, presence: true, if: :cron_expression?
  validates :stream_name, presence: true
  validates :status, presence: true
  validate :stream_name_exists?

  enum :schedule_type, %i[manual interval cron_expression]
  enum :status, %i[disabled healthy pending failed aborted]
  enum :sync_mode, %i[full_refresh incremental]
  enum :sync_interval_unit, %i[minutes hours days]

  belongs_to :workspace
  belongs_to :source, class_name: "Connector"
  belongs_to :destination, class_name: "Connector"
  belongs_to :model
  has_many :sync_runs, dependent: :destroy

  after_initialize :set_defaults, if: :new_record?
  after_save :schedule_sync, if: :schedule_sync?
  after_discard :perform_post_discard_sync

  default_scope -> { kept.order(updated_at: :desc) }

  aasm column: :status, whiny_transitions: true do
    state :pending, initial: true
    state :healthy
    state :failed
    state :disabled

    event :complete do
      transitions from: %i[pending healthy], to: :healthy
    end

    event :fail do
      transitions from: %i[pending healthy], to: :failed
    end

    event :disable do
      transitions from: %i[pending healthy failed], to: :disabled
    end

    event :enable do
      transitions from: :disabled, to: :pending
    end
  end

  def to_protocol
    catalog = destination.catalog
    Multiwoven::Integrations::Protocol::SyncConfig.new(
      model: model.to_protocol,
      source: source.to_protocol,
      destination: destination.to_protocol,
      stream: catalog.stream_to_protocol(
        catalog.find_stream_by_name(stream_name)
      ),
      sync_mode: Multiwoven::Integrations::Protocol::SyncMode[sync_mode],
      destination_sync_mode: Multiwoven::Integrations::Protocol::DestinationSyncMode["insert"],
      cursor_field:,
      current_cursor_field:,
      sync_id: id.to_s
    )
  end

  def set_defaults
    self.status ||= self.class.aasm.initial_state.to_s
  end

  def schedule_cron_expression
    return cron_expression if cron_expression?

    case sync_interval_unit.downcase
    when "minutes"
      # Every X minutes: */X * * * *
      "*/#{sync_interval} * * * *"
    when "hours"
      # Every X hours: 0 */X * * *
      "0 */#{sync_interval} * * *"
    when "days"
      # Every X days: 0 0 */X * *
      "0 0 */#{sync_interval} * *"
    else
      raise ArgumentError, "Invalid sync_interval_unit: #{sync_interval_unit}"
    end
  end

  def schedule_sync?
    (new_record? || saved_change_to_sync_interval? || saved_change_to_sync_interval_unit ||
      saved_change_to_cron_expression? || saved_change_to_status?) && !manual?
  end

  def schedule_sync
    if saved_change_to_status? && status == "disabled"
      Temporal.start_workflow(Workflows::TerminateWorkflow, id, options: { workflow_id: "terminate-#{id}" })
    elsif new_record? || (saved_change_to_status? && status == "pending")
      Temporal.start_workflow(
        Workflows::ScheduleSyncWorkflow,
        id
      )
    end
  rescue StandardError => e
    Utils::ExceptionReporter.report(e, {
                                      sync_id: id
                                    })
    Rails.logger.error "Failed to schedule sync with Temporal. Error: #{e.message}"
  end

  def perform_post_discard_sync
    sync_runs.discard_all
    terminate_workflow_id = "terminate-#{workflow_id}"
    Temporal.start_workflow(Workflows::TerminateWorkflow, workflow_id, options: { workflow_id: terminate_workflow_id })
  rescue StandardError => e
    Utils::ExceptionReporter.report(e, {
                                      sync_id: id
                                    })
    Rails.logger.error "Failed to Run post delete sync. Error: #{e.message}"
  end

  def stream_name_exists?
    return if destination.blank?

    catalog = destination&.catalog
    if catalog.blank?
      errors.add(:catalog, "Catalog is missing")
    elsif catalog.find_stream_by_name(stream_name).blank?
      errors.add(:stream_name,
                 "Add a valid stream_name associated with destination connector")
    end
  end
end
