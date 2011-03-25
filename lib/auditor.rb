require 'uuid'

module Auditor
  class RackApp
    def initialize(app)
      @delegate = app
    end

    def call(env)
      ::Auditor.process do |audit|
        env['auditor.current'] = audit
        begin
          return @delegate.call(env)
        ensure
          env['auditor.current'] = nil
        end
      end
    end
  end

  module Callbacks
    def self.included(klass)
      klass.after_create Auditor::Observer.instance
      klass.after_destroy Auditor::Observer.instance
      klass.after_update Auditor::Observer.instance
    end
  end

  class AuditRecorder
    def initialize()
      @id = UUID.create_v1_faster
      @model_changes = []
      @user = nil
      @info = {}
      @error = nil
    end

    attr_reader :id, :info
    attr_accessor :user, :error

    def record_model_changes(model, action, changes)
      @model_changes << [model.class.name, model.id, action, changes]
    end

    def finish!
      # nothing happened
      return if @model_changes.empty?

      begin
        AuditReport.transaction do
          report = AuditReport.new(:uuid => id.to_s, :began_at => id.timestamp, :finished_at => Time.now)
          report.user = user
          report.info = info
          report.num_changes = @model_changes.length

          report.success = @error.nil?

          report.error = @error.class.name
          report.error_message = @error.message
          report.error_detail = @error.backtrace.join("\n")

          @model_changes.each do |model_type, model_id, action, changes|
            report.audit_changes.build(
              :model_type => model_type,
              :model_id => model_id,
              :action => action,
              :audited_changes => changes
            )
          end

          report.save!
        end
      rescue => e
        puts "--------------------------------------------------------------------------------"
        puts "AUDITOR FAILED TO PERSIST:"
        puts self.inspect
        puts "--------------------------------------------------------------------------------"
        puts "ERROR: #{e.message}"
        puts e.backtrace.join("\n")
        puts "--------------------------------------------------------------------------------"
      end
    end
  end

  class << self
    def current
      x = Thread.current[:audit]
      yield(x) if x and block_given?
    end

    def process()
      audit = AuditRecorder.new()
      Thread.current[:audit] = audit

      begin
        return yield(audit)
      rescue => e
        audit.error = e
        raise
      ensure
        Thread.current[:audit] = nil

        audit.finish!
      end
    end
  end

  class Observer
    def self.instance()
      @instance ||= new()
    end

    def after_destroy(model)
      ::Auditor.current do |audit|
        audit.record_model_changes(model, 'destroy', model.attributes)
      end
    end

    def after_create(model)
      ::Auditor.current do |audit|
        audit.record_model_changes(model, 'create', model.attributes)
      end
    end

    def after_update(model)
      return if model.changes.empty?

      ::Auditor.current do |audit|
        audit.record_model_changes(model, 'update', model.changes)
      end
    end
  end

  class AuditReport < ActiveRecord::Base
    has_many :audit_changes

    belongs_to :user, :polymorphic => true

    validates :uuid, :presence => true

    serialize :info
  end

  class AuditChange < ActiveRecord::Base
    belongs_to :audit_report
    belongs_to :model, :polymorphic => true

    serialize :audited_changes
  end
end
