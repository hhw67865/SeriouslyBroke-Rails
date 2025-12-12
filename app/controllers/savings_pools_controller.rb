# frozen_string_literal: true

class SavingsPoolsController < ApplicationController
  include Searchable

  before_action :set_savings_pool, only: [:show, :edit, :update, :destroy]

  # GET /savings_pools
  def index
    setup_search_state
    @savings_pools = load_filtered_savings_pools
    @recent_entries_by_pool = load_recent_entries_by_pool
  end

  # GET /savings_pools/1
  def show
    # Load recent entries for activity section - avoid N+1
    @recent_entries = @savings_pool.entries
      .includes(item: :category)
      .order(date: :desc)
      .limit(8)

    # Load categories for connected categories section
    # CategoryCalculator uses direct SQL queries, so no eager loading needed
    @connected_categories = @savings_pool.categories
      .order(:name)
  end

  # GET /savings_pools/new
  def new
    @savings_pool = current_user.savings_pools.new
  end

  # GET /savings_pools/1/edit
  def edit; end

  # POST /savings_pools
  def create
    @savings_pool = current_user.savings_pools.new(savings_pool_params)

    if @savings_pool.save
      redirect_to savings_pool_path(@savings_pool), notice: "Savings pool was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /savings_pools/1
  def update
    if @savings_pool.update(savings_pool_params)
      redirect_to savings_pool_path(@savings_pool), notice: "Savings pool was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /savings_pools/1
  def destroy
    @savings_pool.destroy
    redirect_to savings_pools_path, notice: "Savings pool was successfully deleted."
  end

  private

  def setup_search_state
    @search_state = current_search_state(params)
    @query = @search_state[:query] # For backward compatibility
  end

  def load_filtered_savings_pools
    # Load savings pools without eager loading (calculator uses direct SQL)
    savings_pools = current_user.savings_pools

    # Apply search using the new searchable system
    savings_pools = apply_search(savings_pools, { q: params[:q], field: params[:field] })

    savings_pools.order(:name)
  end

  def load_recent_entries_by_pool
    # Load recent entries for each savings pool to avoid N+1 in the view
    # This is more efficient than preloading all entries
    recent_entries = {}
    @savings_pools.each do |pool|
      recent_entries[pool.id] = pool.entries
        .includes(item: :category)
        .order(date: :desc)
        .limit(3)
    end
    recent_entries
  end

  def set_savings_pool
    # Load savings pool without eager loading (calculator uses direct SQL)
    @savings_pool = current_user.savings_pools.find(params[:id])
  end

  def savings_pool_params
    params.require(:savings_pool).permit(:name, :target_amount, :start_date)
  end
end
