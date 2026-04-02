# frozen_string_literal: true

module Categories
  class ItemsController < ApplicationController
    include Searchable

    before_action :set_category
    before_action :set_items, only: [:index]

    # GET /categories/:category_id/items (HTML + JSON)
    def index
      respond_to do |format|
        format.html
        format.json { render json: @category.items.order(:name) }
      end
    end

    # GET /categories/:category_id/items/new
    def new
      @item = @category.items.new
    end

    # POST /categories/:category_id/items
    def create
      @item = @category.items.new(item_params)

      if @item.save
        redirect_to category_items_path(@category), notice: "#{@item.name} was created."
      else
        render :new, status: :unprocessable_content
      end
    end

    # POST /categories/:category_id/items/move
    def move
      target_category = current_user.categories.find(params[:target_category_id])
      items = @category.items.where(id: params[:item_ids])

      if items.empty?
        redirect_to category_items_path(@category), alert: "No items selected."
        return
      end

      Item.transaction do
        items.each { |item| item.move_to_category(target_category) }
      end

      redirect_to category_items_path(@category), notice: "Items moved to #{target_category.name}."
    end

    # GET /categories/:category_id/items/merge?target_item_id=X
    # POST /categories/:category_id/items/merge
    def merge
      @target = @category.items.find(params[:target_item_id])

      if request.get?
        @other_items = @category.items.includes(:entries).where.not(id: @target.id).order(updated_at: :desc)
        render :merge
      else
        source_ids = Array(params[:source_item_ids])
        sources = @category.items.where(id: source_ids)

        if sources.empty?
          redirect_to merge_category_items_path(@category, target_item_id: @target.id), alert: "Select at least one item to merge."
          return
        end

        Item.merge(target: @target, sources: sources)
        redirect_to category_items_path(@category), notice: "#{sources.size} item(s) merged into #{@target.name}."
      end
    end

    private

    def set_category
      @category = current_user.categories.find(params[:category_id])
    end

    def set_items
      @search_state = current_search_state(params)
      items = @category.items.includes(:entries).order(updated_at: :desc)
      @items = apply_search(items, { q: params[:q], field: params[:field] })
    end

    def item_params
      params.expect(item: [:name, :description])
    end
  end
end
