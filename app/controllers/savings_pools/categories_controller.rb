# frozen_string_literal: true

class SavingsPools::CategoriesController < ApplicationController
  before_action :set_savings_pool

  # GET /savings_pools/:id/categories
  def index
    # Only load what's actually accessed in Ruby code:
    # - savings_pool for conflict detection ("Connected to other goal")
    # CategoryCalculator uses direct SQL queries, not Ruby associations
    @all_categories = current_user.categories
                                  .where(category_type: ['savings', 'expense'])
                                  .includes(:savings_pool)
                                  .order(:name)
    @connected_category_ids = @savings_pool.categories.pluck(:id)
    
    # Group categories to show conflicts
    @categories_with_other_pools = @all_categories.where.not(savings_pool: [nil, @savings_pool])
                                                  .group_by(&:savings_pool)
  end

  # PATCH /savings_pools/:id/categories
  def update
    category_ids = params[:category_ids] || []
    
    # Remove categories that are no longer selected
    @savings_pool.categories.where.not(id: category_ids).update_all(savings_pool_id: nil)
    
    # Add newly selected categories
    current_user.categories.where(id: category_ids).update_all(savings_pool_id: @savings_pool.id)
    
    redirect_to @savings_pool, notice: "Categories updated successfully!"
  end

  private

  def set_savings_pool
    @savings_pool = current_user.savings_pools.find(params[:id])
  end
end 