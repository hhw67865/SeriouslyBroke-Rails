# frozen_string_literal: true

module Categories
  class ItemsController < ApplicationController
    include Searchable

    before_action :set_category
    before_action :set_items, only: [:index]
    before_action :set_target_item, only: [:merge, :perform_merge]

    # GET /categories/:category_id/items (HTML + JSON)
    def index
      respond_to do |format|
        format.html
        format.json { render json: items_json(@category.items.order(:name)) }
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
      items = @category.items.where(id: params[:item_ids])
      return redirect_to category_items_path(@category), alert: "No items selected." if items.empty?

      target = current_user.categories.find(params[:target_category_id])
      refusal = move_all(items, target)
      return redirect_to category_items_path(@category), alert: refusal if refusal

      redirect_to category_items_path(@category), notice: "Items moved to #{target.name}."
    end

    # GET /categories/:category_id/items/merge?target_item_id=X
    def merge
      @other_items = @category.items.includes(:entries).where.not(id: @target.id).order(updated_at: :desc)
    end

    # POST /categories/:category_id/items/merge
    def perform_merge
      sources = @category.items.where(id: Array(params[:source_item_ids])).to_a

      if sources.empty?
        redirect_to merge_category_items_path(@category, target_item_id: @target.id), alert: "Select at least one item to merge."
        return
      end

      return refuse_merge(sources) unless Item.merge(target: @target, sources: sources)

      redirect_to category_items_path(@category), notice: "#{sources.size} item(s) merged into #{@target.name}."
    end

    private

    # What the item select's own option carries: its history, so picking one can offer to fill
    # the amount from the last time without a second round trip. One query for every last entry.
    def items_json(items)
      lasts = Entry.latest_per_item(items.map(&:id)).index_by(&:item_id)
      items.map { |item| item_json(item, lasts[item.id]) }
    end

    def item_json(item, last)
      {
        id: item.id,
        name: item.name,
        last_amount: last && format("%.2f", last.amount),
        last_date: last&.date&.iso8601
      }
    end

    # Either every item moves or none does, so a refusal takes the whole batch back with it.
    def move_all(items, target)
      refusal = nil
      Item.transaction do
        items.each do |item|
          next if item.move_to_category(target)

          refusal = item.errors.full_messages.to_sentence
          raise ActiveRecord::Rollback
        end
      end
      refusal
    end

    def refuse_merge(sources)
      refusal = sources.flat_map { |source| source.errors.full_messages }.to_sentence
      redirect_to merge_category_items_path(@category, target_item_id: @target.id), alert: refusal
    end

    def set_category
      @category = current_user.categories.find(params[:category_id])
    end

    def set_items
      @search_state = current_search_state(params)
      items = @category.items.includes(:entries).order(updated_at: :desc)
      @items = apply_search(items, { q: params[:q], field: params[:field] })
    end

    def set_target_item
      @target = @category.items.find(params[:target_item_id])
    end

    def item_params
      params.expect(item: [:name, :description])
    end
  end
end
