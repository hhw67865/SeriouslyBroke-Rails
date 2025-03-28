# frozen_string_literal: true

class ItemsController < ApplicationController
  before_action :set_item, only: [:show, :edit, :update, :destroy]
  before_action :set_category, only: [:new, :create]

  # GET /items
  def index
    @items = current_user.items.includes(:category)
  end

  # GET /items/1
  def show; end

  # GET /items/new
  def new
    @item = @category.items.new
  end

  # GET /items/1/edit
  def edit; end

  # POST /items
  def create
    @item = @category.items.new(item_params)

    if @item.save
      redirect_to items_path, notice: "Item was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /items/1
  def update
    if @item.update(item_params)
      redirect_to items_path, notice: "Item was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /items/1
  def destroy
    @item.destroy
    redirect_to items_path, notice: "Item was successfully deleted."
  end

  private

  def set_item
    @item = current_user.items.find(params[:id])
  end

  def set_category
    @category = current_user.categories.find(params[:category_id]) if params[:category_id]
  end

  def item_params
    params.require(:item).permit(:name, :description, :frequency, :category_id)
  end
end
