# frozen_string_literal: true

class EntriesController < ApplicationController
  before_action :set_entry, only: [:show, :edit, :update, :destroy]
  before_action :set_item, only: [:new, :create]

  # GET /entries
  def index
    @entries = current_user.entries.includes(item: :category)
    
    # Filter by type using existing scopes
    case params[:type]
    when 'expenses'
      @entries = @entries.expenses
    when 'income'
      @entries = @entries.incomes
    when 'savings'
      @entries = @entries.savings
    end
    
    @entries = @entries.order(date: :desc)
    @current_type = params[:type] || 'all'
  end

  # GET /entries/1
  def show; end

  # GET /entries/new
  def new
    @entry = @item ? @item.entries.new : Entry.new
    @entry.date = Time.current
  end

  # GET /entries/1/edit
  def edit; end

  # POST /entries
  def create
    @entry = Entry.new(entry_params)

    if @entry.save
      redirect_to entries_path, notice: "Entry was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /entries/1
  def update
    if @entry.update(entry_params)
      redirect_to entries_path, notice: "Entry was successfully updated."
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
