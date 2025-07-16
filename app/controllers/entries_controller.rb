# frozen_string_literal: true

class EntriesController < ApplicationController
  include Searchable
  
  before_action :set_entry, only: [:show, :edit, :update, :destroy]
  before_action :set_item, only: [:new, :create]

  # GET /entries
  def index
    @entries = build_entries_query
    @current_type = params[:type] || 'all'
    @current_sort = params[:sort]
    @current_direction = params[:direction] == 'desc' ? 'desc' : 'asc'
    @search_state = current_search_state(params)
  end

  # GET /entries/1
  def show
  end

  # GET /entries/new
  def new
    @entry = current_user.entries.build
    @entry.item = @item if @item
  end

  # GET /entries/1/edit
  def edit
  end

  # POST /entries
  def create
    @entry = current_user.entries.build(entry_params)
    @entry.item = @item if @item

    if @entry.save
      redirect_to entries_path, notice: 'Entry was successfully created.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /entries/1
  def update
    if @entry.update(entry_params)
      redirect_to entry_path(@entry), notice: 'Entry was successfully updated.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /entries/1
  def destroy
    @entry.destroy
    redirect_to entries_path, notice: 'Entry was successfully deleted.'
  end

  private

  def build_entries_query
    entries = current_user.entries.includes(item: :category)
    
    # Apply type filtering
    entries = apply_type_filter(entries)
    
    # Apply search
    entries = apply_search(entries, { q: params[:q], field: params[:field] })
    
    # Apply sorting
    entries = apply_sorting(entries)
    
    entries
  end

  def apply_type_filter(entries)
    case params[:type]
    when 'expenses'
      entries.expenses
    when 'income'
      entries.incomes
    when 'savings'
      entries.savings
    else
      entries
    end
  end

  def apply_sorting(entries)
    sort_column = params[:sort]
    sort_direction = params[:direction] == 'desc' ? 'desc' : 'asc'
    
    case sort_column
    when 'date'
      entries.order(date: sort_direction)
    when 'amount'
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

  def entry_params
    params.require(:entry).permit(:amount, :date, :description, :item_id)
  end
end
