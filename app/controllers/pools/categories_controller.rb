# frozen_string_literal: true

module Pools
  class CategoriesController < ApplicationController
    before_action :set_pool

    # GET /pools/:id/categories
    def index
      # Only load what's actually accessed in Ruby code:
      # - pool for conflict detection ("Connected to other goal")
      # CategoryCalculator uses direct SQL queries, not Ruby associations
      @all_categories = current_user.categories
        .where(category_type: ["savings", "expense"])
        .includes(:pool)
        .order(:name)
      @connected_category_ids = @pool.categories.pluck(:id)

      # Group categories to show conflicts
      @categories_with_other_pools = @all_categories.where.not(pool: [nil, @pool])
        .group_by(&:pool)
    end

    # PATCH /pools/:id/categories
    def update
      category_ids = params[:category_ids] || []

      # Remove categories that are no longer selected
      @pool.categories.where.not(id: category_ids).find_each do |category|
        category.update(pool_id: nil)
      end

      # Add newly selected categories
      current_user.categories.where(id: category_ids).find_each do |category|
        category.update(pool_id: @pool.id)
      end

      redirect_to @pool, notice: "Categories updated successfully!"
    end

    private

    def set_pool
      @pool = current_user.pools.find(params[:id])
    end
  end
end
