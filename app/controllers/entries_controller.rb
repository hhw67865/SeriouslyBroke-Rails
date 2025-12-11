# frozen_string_literal: true

class EntriesController < ApplicationController
  include Searchable

  before_action :set_entry, only: [:edit, :update, :destroy]
  before_action :set_item, only: [:new, :create]
  before_action :load_options, only: [:new, :edit, :create, :update]
  before_action :set_previous_url, only: [:new, :create, :edit, :update]

  # GET /entries
  def index
    @entries = build_entries_query
    @current_type = params[:type] || "all"
    @current_sort = params[:sort]
    @current_direction = params[:direction] == "desc" ? "desc" : "asc"
    @search_state = current_search_state(params)
  end

  # GET /entries/new
  def new
    @entry = Entry.new
    @entry.item = @item if @item
    @entry.build_item
  end

  # GET /entries/1/edit
  def edit; end

  # POST /entries
  def create
    @entry = Entry.new(entry_params)
    @entry.item = @item if @item

    if @entry.save
      redirect_to previous_path, notice: "Entry was successfully created."
    else
      @entry.build_item
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /entries/1
  def update
    if @entry.update(entry_params)
      redirect_to previous_path, notice: "Entry was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /entries/1
  def destroy
    @entry.destroy
    redirect_to entries_path, notice: "Entry was successfully deleted."
  end

  private

  def build_entries_query
    entries = current_user.entries.includes(item: :category)

    # Apply type filtering
    entries = apply_type_filter(entries)

    # Apply search
    entries = apply_search(entries, { q: params[:q], field: params[:field] })

    # Apply sorting and pagination
    entries = apply_sorting(entries)
    entries.page(params[:page])
  end

  def apply_type_filter(entries)
    case params[:type]
    when "expenses"
      entries.expenses
    when "income"
      entries.incomes
    when "savings"
      entries.savings
    else
      entries
    end
  end

  def apply_sorting(entries)
    sort_column = params[:sort]
    sort_direction = params[:direction] == "desc" ? "desc" : "asc"

    case sort_column
    when "date"
      entries.order(date: sort_direction)
    when "amount"
      entries.order(amount: sort_direction)
    else
      # Default sorting by date (newest first)
      entries.order(date: :desc)
    end
  end

  def set_entry
    @entry = current_user.entries.find(params[:id])
  end

  def set_item
    @item = current_user.items.find(params[:item_id]) if params[:item_id]
  end

  def load_options
    @categories = current_user.categories.order(:name)
  end

  def entry_params
    params.require(:entry).permit(:amount, :date, :description, :item_id).tap do |permitted_params|
      permitted_params[:item_attributes] = item_attributes if permitted_params[:item_id].blank? && params.dig(:entry, :item_attributes, :name).present?
    end
  end

  def item_attributes
    params.require(:entry).require(:item_attributes).permit(:name).tap do |attrs|
      # Set category_id from the category select if creating a new item
      attrs[:category_id] = params[:category_id] if params[:category_id].present?
    end
  end

  def set_previous_url
    @previous_url = params[:previous_url]
    return unless @previous_url.blank? && request.referer.present? && URI(request.referer).path != new_entry_path
    @previous_url = request.referer
  end

  def previous_path
    if @previous_url.present? && @previous_url.include?("calendar")
      calendar_week_path(date: @entry.date)
    else
      @previous_url || entries_path
    end
  end
end
