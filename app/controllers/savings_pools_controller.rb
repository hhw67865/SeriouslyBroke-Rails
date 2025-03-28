# frozen_string_literal: true

class SavingsPoolsController < ApplicationController
  before_action :set_savings_pool, only: [:show, :edit, :update, :destroy]

  # GET /savings_pools
  def index
    @savings_pools = current_user.savings_pools
  end

  # GET /savings_pools/1
  def show; end

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
      redirect_to savings_pools_path, notice: "Savings pool was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /savings_pools/1
  def update
    if @savings_pool.update(savings_pool_params)
      redirect_to savings_pools_path, notice: "Savings pool was successfully updated."
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

  def set_savings_pool
    @savings_pool = current_user.savings_pools.find(params[:id])
  end

  def savings_pool_params
    params.require(:savings_pool).permit(:name, :target_amount)
  end
end
