# frozen_string_literal: true

class ItemsController < ApplicationController
  before_action :set_item, only: [:edit, :update, :destroy]

  # GET /items/1/edit
  def edit; end

  # PATCH/PUT /items/1
  def update
    if @item.update(item_params)
      redirect_to category_path(@item.category), notice: "Item was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /items/1
  def destroy
    category = @item.category
    @item.destroy
    redirect_to category_path(category), notice: "Item was successfully deleted."
  end

  private

  def set_item
    @item = current_user.items.find(params[:id])
  end

  def item_params
    params.require(:item).permit(:name, :description, :frequency, :category_id)
  end
end
