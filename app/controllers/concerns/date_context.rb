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
      session.delete(:date_session_time)
      return
    end

    # Reset the selection if the signed-in user changed or session expired (1 hour)
    session_expired = session[:date_session_time] && session[:date_session_time] < 1.hour.ago
    if session[:selected_user_id] != current_user.id || session_expired
      session[:selected_user_id] = current_user.id
      session[:selected_month] = nil
      session[:selected_year] = nil
      session[:date_session_time] = Time.current
    end

    # Only update session from params if they're provided (from date selector form)
    if params[:month].present? && params[:year].present?
      month_param = params[:month].to_i
      year_param  = params[:year].to_i
      if month_param.between?(1, 12) && year_param > 1900
        session[:selected_month] = month_param
        session[:selected_year]  = year_param
        
        # Redirect to clean URL without date params but preserve other query params
        if request.get?
          clean_params = request.query_parameters.except('month', 'year')
          redirect_url = clean_params.any? ? "#{request.path}?#{clean_params.to_query}" : request.path
          redirect_to redirect_url and return
        end
      end
    end

    # Always use session values, default to current month/year if not set
    session[:selected_month] ||= Date.current.month
    session[:selected_year]  ||= Date.current.year
    session[:date_session_time] = Time.current  # Reset expiration timer on every request

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

end


