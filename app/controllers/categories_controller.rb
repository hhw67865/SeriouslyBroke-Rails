class CategoriesController < ApplicationController
  before_action :set_category, only: [:show, :edit, :update, :destroy]
  before_action :get_categories, only: [:index]

  # GET /categories
  def index
    # Categories are filtered in the get_categories before_action
  end

  # GET /categories/1
  def show
  end

  # GET /categories/new
  def new
    @category = current_user.categories.new
    @category.category_type = params[:type] if params[:type].present?
  end

  # GET /categories/1/edit
  def edit
  end

  # POST /categories
  def create
    @category = current_user.categories.new(category_params)

    if @category.save
      redirect_to categories_path(type: @category.category_type), notice: 'Category was successfully created.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /categories/1
  def update
    if @category.update(category_params)
      redirect_to categories_path(type: @category.category_type), notice: 'Category was successfully updated.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /categories/1
  def destroy
    category_type = @category.category_type
    @category.destroy
    redirect_to categories_path(type: category_type), notice: 'Category was successfully deleted.'
  end

  private

  def set_category
    @category = current_user.categories.find(params[:id])
  end

  def category_params
    params.require(:category).permit(:name, :category_type, :color, :savings_pool_id)
  end

  def get_categories
    @type = params[:type] || 'expense'
    @query = params[:query]
    
    @categories = current_user.categories
                              .with_type(@type)
                              .search(@query)
                              .order(name: :asc)
  end
end
