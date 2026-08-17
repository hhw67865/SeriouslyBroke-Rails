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

      # DISCONNECTING HANDS THE CATEGORY BACK TO AN ACCOUNT, IT DOES NOT NULL IT (plan 3, task 3).
      # This wrote `pool_id: nil`, and `Category belongs_to :pool` refuses that now — `update`
      # returns false, nothing changes, and the user reads "Categories updated successfully!" over a
      # category that is still connected. Found in the browser suite, not reasoned about.
      #
      # The destination is the SAME ONE `Pool#hand_categories_to_the_account` uses when a pool is
      # destroyed: the pool's own account, which is what keeps `Σ pools` conserved — the category's
      # whole history moves into the buffer rather than out of the tree. A pool with no account
      # falls back to the user's nominated one, and a user with neither has nowhere to put the
      # category, so the disconnect is refused rather than half-written.
      @pool.categories.where.not(id: category_ids).find_each do |category|
        category.update(pool: disconnect_destination)
      end

      # Add newly selected categories
      current_user.categories.where(id: category_ids).find_each do |category|
        category.update(pool_id: @pool.id)
      end

      redirect_to @pool, notice: "Categories updated successfully!"
    end

    private

    def disconnect_destination = @pool.account || current_user.default_account

    def set_pool
      @pool = current_user.pools.find(params[:id])
    end
  end
end
