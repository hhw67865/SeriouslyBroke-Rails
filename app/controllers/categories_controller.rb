# frozen_string_literal: true

class CategoriesController < ApplicationController
  include Searchable
  include PeriodContext

  before_action :set_category, only: [:show, :edit, :update, :destroy, :toggle_tracked]
  before_action :set_categories, only: [:index]

  # GET /categories
  def index
    # Categories are filtered in the get_categories before_action
  end

  # GET /categories/1
  #
  # The budget block is spec §8.1's, and it is built for EXPENSE categories only because that is
  # the only kind that can carry a cap or point at an envelope — an income or savings category has
  # no budget state to be in. Nil for the others, and the view renders nothing for a nil.
  # THE POOL CARD GETS THE SAME OBJECT, and one instance serves both blocks (2d task 6). The card
  # is older than the budget block and rendered savings chrome for every pool it was given — an
  # ACCOUNT read "Savings Pool / Target: $1,000.00 / -30% complete", a savings progress bar drawn
  # on a buffer — so it now asks what its pool IS, which is exactly the question this presenter
  # already answers for the block above it.
  #
  # It is built for every pooled category, not just `expense?` ones: a SAVINGS category points at a
  # pool too, and that is the arm whose rendering does not change. Memoised, so an expense category
  # pointing at an envelope builds ONE PoolStatus for both blocks rather than two that could
  # disagree about the same envelope on the same page.
  def show
    @budget_block = category_pool_presenter if @category.expense?
    @pool_card = category_pool_presenter if @category.pool.present?
  end

  # GET /categories/new
  def new
    @category = current_user.categories.new
    @category.category_type = params[:type] if params[:type].present?
  end

  # GET /categories/1/edit
  def edit; end

  # POST /categories
  def create
    @category = current_user.categories.new(category_params)

    if @category.save
      redirect_to categories_path(type: @category.category_type), notice: "Category was successfully created."
    else
      render :new, status: :unprocessable_content
    end
  end

  # PATCH/PUT /categories/1
  def update
    if @category.update(category_params)
      redirect_to categories_path(type: @category.category_type), notice: "Category was successfully updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  # DELETE /categories/1
  def destroy
    category_type = @category.category_type
    @category.destroy
    redirect_to categories_path(type: category_type), notice: "Category was successfully deleted."
  end

  def toggle_tracked
    if @category.update(tracked: !@category.tracked?)
      redirect_back_or_to(reports_path)
    else
      redirect_back_or_to(reports_path, alert: "Could not update category.")
    end
  end

  def update_tracked
    params[:categories]&.each do |id, attrs|
      current_user.categories.find_by(id: id)&.update(tracked: attrs[:tracked] == "1")
    end

    redirect_back_or_to(reports_path)
  end

  private

  def category_pool_presenter
    @category_pool_presenter ||= CategoryBudgetPresenter.new(category: @category)
  end

  def set_category
    @category = current_user.categories.find(params[:id])

    # Preload entries with their items for the recent activity section
    @recent_entries = @category.entries.includes(:item).order(date: :desc).limit(5)
  end

  def category_params
    params.expect(category: [:name, :category_type, :color, :pool_id])
  end

  def set_categories
    @type = params[:type] || "expense"
    @search_state = current_search_state(params)
    @query = @search_state[:query] # For backward compatibility

    categories = current_user.categories.with_type(@type)

    # Apply search using the new searchable system
    categories = apply_search(categories, { q: params[:q], field: params[:field] })

    @categories = categories.order(name: :asc)
  end
end
