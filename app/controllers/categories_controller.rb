# frozen_string_literal: true

class CategoriesController < ApplicationController
  include Searchable

  before_action :set_category, only: [:show, :edit, :update, :destroy]
  before_action :set_categories, only: [:index]
  before_action :set_period, only: [:show]

  helper_method :current_period

  # GET /categories
  def index
    # Categories are filtered in the get_categories before_action
  end

  # GET /categories/1
  def show; end

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

  def items
    category = current_user.categories.find(params[:id])
    render json: category.items.order(:name), status: :ok
  end

  private

  def set_category
    @category = current_user.categories.find(params[:id])

    # Preload entries with their items for the recent activity section
    @recent_entries = @category.entries.includes(:item).order(date: :desc).limit(5)
  end

  def category_params
    params.expect(category: [:name, :category_type, :color, :savings_pool_id])
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

  def set_period
    @period = params[:period] == "ytd" ? :ytd : :monthly
  end

  def current_period
    @period || :monthly
  end
end
