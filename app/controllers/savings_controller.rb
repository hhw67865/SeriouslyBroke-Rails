# frozen_string_literal: true

class SavingsController < ApplicationController
  include SavingsPageState

  def show = assign_savings_state
end
