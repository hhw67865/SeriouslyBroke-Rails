# frozen_string_literal: true

class BudgetsController < ApplicationController
  before_action :set_budget, only: [:edit, :update, :destroy]
  before_action :set_category, only: [:new, :create]

  # GET /budgets/new
  def new
    @budget = @category ? @category.build_budget : Budget.new
  end

  # GET /budgets/1/edit
  def edit; end

  # POST /budgets
  def create
    @budget = Budget.new(budget_params)

    if @budget.save
      redirect_to category_path(@budget.category), notice: "Budget was successfully created."
    else
      render :new, status: :unprocessable_content
    end
  end

  # PATCH/PUT /budgets/1
  def update
    if @budget.update(budget_params)
      redirect_to category_path(@budget.category), notice: "Budget was successfully updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  # DELETE /budgets/1
  def destroy
    category = @budget.category
    @budget.destroy
    redirect_to category_path(category), notice: "Budget was successfully deleted."
  end

  private

  def set_budget
    @budget = current_user.budgets.find(params[:id])
  end

  def set_category
    @category = current_user.categories.expenses.find(params[:category_id]) if params[:category_id]
  end

  def budget_params
    params.expect(budget: [:amount, :period, :category_id])
  end
end
