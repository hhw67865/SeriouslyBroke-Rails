# frozen_string_literal: true

module Users
  class RegistrationsController < Devise::RegistrationsController
    before_action :reject_bots, only: :create
    before_action :configure_permitted_parameters

    def create
      super
    end

    protected

    def configure_permitted_parameters
      devise_parameter_sanitizer.permit(:sign_up, keys: [:name])
      devise_parameter_sanitizer.permit(:account_update, keys: [:name, :email_confirmation])
    end

    def update_resource(resource, params)
      if password_change?(params) || email_change?(resource, params)
        super
      else
        resource.update_without_password(params.except(:current_password))
      end
    end

    def after_update_path_for(_resource)
      account_path
    end

    private

    def reject_bots
      return if params[:website].blank?

      redirect_to root_path
    end

    def password_change?(params)
      params[:password].present? || params[:password_confirmation].present?
    end

    def email_change?(resource, params)
      params[:email].present? && params[:email] != resource.email
    end
  end
end
