# frozen_string_literal: true

class PoolsController < ApplicationController
  include Searchable

  before_action :set_pool, only: [:show, :edit, :update, :destroy]

  # GET /pools
  def index
    setup_search_state
    @pools = load_filtered_pools
    @timelines_by_pool = load_timelines_by_pool
  end

  # GET /pools/1
  # `Pool#timeline` IS THE POST-CUTOVER CONTRIBUTION HISTORY (plan 3, task 5) — movements in and
  # out plus the spending of the categories pointing here, which is exactly what the two money-flow
  # tiles on this page sum. It preloads and limits itself, so the controller no longer builds the
  # scope by hand.
  def show
    @timeline = @pool.timeline(limit: 8)

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
      redirect_to pool_path(@pool), notice: "Pool was successfully created."
    else
      render :new, status: :unprocessable_content
    end
  end

  # PATCH/PUT /pools/1
  def update
    if @pool.update(pool_params)
      redirect_to pool_path(@pool), notice: "Pool was successfully updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  # DELETE /pools/1
  def destroy
    if @pool.destroy
      redirect_to pools_path, notice: "Pool was successfully deleted."
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
    pools = current_user.pools.savings_pools

    # Apply search using the new searchable system
    pools = apply_search(pools, { q: params[:q], field: params[:field] })

    pools.order(:name)
  end

  # The card's three-row activity strip, per goal. Bounded per pool rather than loaded whole, the
  # same shape it has always had; `Pool#timeline` does its own preloading.
  # KEYED BY ID, not by the record — `_pool.html.erb` looks its row up with `dig(pool.id)`, and an
  # `index_with` keyed on the pool object misses every time, silently: the card falls through to its
  # no-activity branch and prints "Still needed" for a goal that has a history. Caught at the
  # browser, not by a type error.
  def load_timelines_by_pool
    @pools.to_h { |pool| [pool.id, pool.timeline(limit: 3)] }
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
        # A pool is an account, a budget envelope or a savings goal, and a non-account
        # names the account it sits inside — neither is derivable from the other params,
        # so both must be assignable or every pool created here is a savings goal in the
        # default account-less shape. `priority` orders the funding waterfall.
        :pool_type,
        :account_id,
        :priority,
        :create_expense_category
      ]
    )
  end
end
