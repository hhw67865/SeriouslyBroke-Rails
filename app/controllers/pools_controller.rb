# frozen_string_literal: true

class PoolsController < ApplicationController
  include Searchable

  before_action :set_pool, only: [:show, :edit, :update, :destroy]

  # GET /pools
  def index
    setup_search_state
    @pools = load_filtered_pools
    @recent_entries_by_pool = load_recent_entries_by_pool
  end

  # GET /pools/1
  def show
    @recent_entries = @pool.timeline_entries
      .includes(item: :category)
      .order(date: :desc)
      .limit(8)

    # Load categories for connected categories section
    # CategoryCalculator uses direct SQL queries, so no eager loading needed
    @connected_categories = @pool.categories
      .order(:name)
  end

  # GET /pools/new
  def new
    @pool = current_user.pools.new
  end

  # GET /pools/1/edit
  def edit; end

  # POST /pools
  def create
    @pool = current_user.pools.new(pool_params)

    if @pool.save
      redirect_to pool_path(@pool), notice: "Savings pool was successfully created."
    else
      render :new, status: :unprocessable_content
    end
  end

  # PATCH/PUT /pools/1
  def update
    if @pool.update(pool_params)
      redirect_to pool_path(@pool), notice: "Savings pool was successfully updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  # DELETE /pools/1
  def destroy
    if @pool.destroy
      redirect_to pools_path, notice: "Savings pool was successfully deleted."
    else
      redirect_to pool_path(@pool), alert: @pool.errors[:base].to_sentence
    end
  end

  private

  def setup_search_state
    @search_state = current_search_state(params)
    @query = @search_state[:query] # For backward compatibility
  end

  def load_filtered_pools
    # Load savings pools without eager loading (calculator uses direct SQL)
    pools = current_user.pools

    # Apply search using the new searchable system
    pools = apply_search(pools, { q: params[:q], field: params[:field] })

    pools.order(:name)
  end

  def load_recent_entries_by_pool
    # Load recent entries for each savings pool to avoid N+1 in the view
    # This is more efficient than preloading all entries
    recent_entries = {}
    @pools.each do |pool|
      recent_entries[pool.id] = pool.timeline_entries
        .includes(item: :category)
        .order(date: :desc)
        .limit(3)
    end
    recent_entries
  end

  def set_pool
    # Load savings pool without eager loading (calculator uses direct SQL)
    @pool = current_user.pools.find(params[:id])
  end

  def pool_params
    params.expect(
      pool: [
        :name,
        :target_amount,
        :start_date,
        :create_expense_category,
        :create_savings_category
      ]
    )
  end
end
