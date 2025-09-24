# frozen_string_literal: true

module DateContext
  extend ActiveSupport::Concern

  included do
    before_action :set_selected_month_year
    helper_method :selected_month, :selected_year, :selected_date
  end

  private

  def set_selected_month_year
    # If no authenticated user, clear any persisted month/year and exit
    unless current_user
      session.delete(:selected_month)
      session.delete(:selected_year)
      session.delete(:selected_user_id)
      return
    end

    # Reset the selection if the signed-in user changed
    if session[:selected_user_id] != current_user.id
      session[:selected_user_id] = current_user.id
      session[:selected_month] = nil
      session[:selected_year] = nil
    end

    if params[:month].present? && params[:year].present?
      month_param = params[:month].to_i
      year_param  = params[:year].to_i
      if month_param.between?(1, 12) && year_param > 1900
        session[:selected_month] = month_param
        session[:selected_year]  = year_param
      end
    else
      session[:selected_month] ||= Date.current.month
      session[:selected_year]  ||= Date.current.year
    end

    @selected_month = session[:selected_month]
    @selected_year  = session[:selected_year]
  end

  def selected_month
    @selected_month || session[:selected_month]
  end

  def selected_year
    @selected_year || session[:selected_year]
  end

  def selected_date
    return nil unless selected_month && selected_year
    Date.new(selected_year, selected_month, 1)
  end

  # Ensure all generated URLs include the current month/year automatically for authed users
  def default_url_options
    base = super
    return base unless current_user && selected_month && selected_year
    base.merge(month: selected_month, year: selected_year)
  end
end


