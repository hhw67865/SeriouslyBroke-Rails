# frozen_string_literal: true

module DateContext
  extend ActiveSupport::Concern

  included do
    before_action :set_selected_month_year
    helper_method :selected_month, :selected_year, :selected_date
  end

  private

  def set_selected_month_year
    return clear_date_session unless current_user

    reset_if_user_changed_or_expired
    update_session_from_params
    set_default_values
  end

  def clear_date_session
    session.delete(:selected_month)
    session.delete(:selected_year)
    session.delete(:selected_user_id)
    session.delete(:date_session_time)
  end

  def reset_if_user_changed_or_expired
    return unless user_changed? || session_expired?

    reset_session_data
  end

  def user_changed?
    session[:selected_user_id] != current_user.id
  end

  def session_expired?
    session[:date_session_time] && session[:date_session_time] < 1.hour.ago
  end

  def reset_session_data
    session[:selected_user_id] = current_user.id
    session[:selected_month] = nil
    session[:selected_year] = nil
    session[:date_session_time] = Time.current
  end

  def update_session_from_params
    return unless date_params_present?

    month_param, year_param = extract_date_params
    return unless valid_date_params?(month_param, year_param)

    update_session_with_params(month_param, year_param)
    redirect_to_clean_url if request.get?
  end

  def date_params_present?
    params[:month].present? && params[:year].present?
  end

  def extract_date_params
    [params[:month].to_i, params[:year].to_i]
  end

  def valid_date_params?(month, year)
    month.between?(1, 12) && year > 1900
  end

  def update_session_with_params(month, year)
    session[:selected_month] = month
    session[:selected_year] = year
  end

  def redirect_to_clean_url
    clean_params = request.query_parameters.except("month", "year")
    redirect_url = clean_params.any? ? "#{request.path}?#{clean_params.to_query}" : request.path
    redirect_to redirect_url
  end

  def set_default_values
    session[:selected_month] ||= Date.current.month
    session[:selected_year] ||= Date.current.year
    session[:date_session_time] = Time.current

    @selected_month = session[:selected_month]
    @selected_year = session[:selected_year]
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
end
