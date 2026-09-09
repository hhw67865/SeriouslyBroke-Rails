# frozen_string_literal: true

class SettingsController < ApplicationController
  def show; end

  def toggle_theme
    current_user.toggle_theme!
    redirect_back_or_to settings_path
  end

  def toggle_ming_mode
    current_user.update(ming_mode: !current_user.ming_mode?)
    redirect_back_or_to settings_path
  end
end
