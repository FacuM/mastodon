# frozen_string_literal: true

module Admin
  class ReportsController < BaseController
    before_action :set_report, except: [:index]

    def index
      authorize :report, :index?
      @reports = filtered_reports.page(params[:page])
    end

    def show
      authorize @report, :show?
      @form = Form::StatusBatch.new
    end

    def update
      authorize @report, :update?
      process_report
      redirect_to admin_report_path(@report)
    end

    private

    def process_report
      case params[:outcome].to_s
      when 'resolve'
        @report.update!(action_taken_by_current_attributes)
        log_action :resolve, @report
      when 'suspend'
        Admin::SuspensionWorker.perform_async(@report.target_account.id)
        log_action :resolve, @report
        log_action :suspend, @report.target_account
        resolve_all_target_account_reports
      when 'silence'
        @report.target_account.update!(silenced: true)
        log_action :resolve, @report
        log_action :silence, @report.target_account
        resolve_all_target_account_reports
      else
        raise ActiveRecord::RecordNotFound
      end
    end

    def action_taken_by_current_attributes
      { action_taken: true, action_taken_by_account_id: current_account.id }
    end

    def resolve_all_target_account_reports
      unresolved_reports_for_target_account.update_all(
        action_taken_by_current_attributes
      )
    end

    def unresolved_reports_for_target_account
      Report.where(
        target_account: @report.target_account
      ).unresolved
    end

    def filtered_reports
      ReportFilter.new(filter_params).results.order(id: :desc).includes(
        :account,
        :target_account
      )
    end

    def filter_params
      params.permit(
        :account_id,
        :resolved,
        :target_account_id
      )
    end

    def set_report
      @report = Report.find(params[:id])
    end
  end
end
