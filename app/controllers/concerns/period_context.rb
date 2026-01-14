# frozen_string_literal: true

module PeriodContext
  extend ActiveSupport::Concern

  included do
    before_action :set_period
    helper_method :current_period
  end

  private

  def set_period
    @period = params[:period] == "ytd" ? :ytd : :monthly
  end

  def current_period
    @period || :monthly
  end
end
