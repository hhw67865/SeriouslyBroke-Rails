# frozen_string_literal: true

class DashboardController < ApplicationController
  def index
    # Load dashboard data
    @expense_categories = current_user.categories.expenses.includes(:budget)
    @income_categories = current_user.categories.incomes
    @savings_pools = current_user.savings_pools
    
    # Recent entries
    @recent_entries = current_user.entries.includes(item: :category)
                                 .order(date: :desc)
                                 .limit(5)
  end
end
