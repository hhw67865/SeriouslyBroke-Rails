# frozen_string_literal: true

class PagesController < ApplicationController
  skip_before_action :authenticate_user!, only: [:home, :about, :privacy, :terms]
  
  def home
    redirect_to dashboard_path if user_signed_in?
  end

  def about
  end

  def privacy
  end

  def terms
  end
end
