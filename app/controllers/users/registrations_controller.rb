# frozen_string_literal: true

module Users
  class RegistrationsController < Devise::RegistrationsController
    before_action :reject_bots, only: :create

    def create
      super
    end

    private

    def reject_bots
      return if params[:website].blank?

      redirect_to root_path
    end
  end
end
