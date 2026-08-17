# frozen_string_literal: true

class EntriesController < ApplicationController
  include Searchable

  before_action :set_entry, only: [:edit, :update, :destroy]
  before_action :set_item, only: [:new, :create]
  before_action :load_options, only: [:new, :edit, :create, :update]
  before_action :set_previous_url, only: [:new, :create, :edit, :update]

  helper_method :entry_impact

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
      render :new, status: :unprocessable_content
    end
  end

  # PATCH/PUT /entries/1
  def update
    if @entry.update(entry_params)
      redirect_to previous_path, notice: "Entry was successfully updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  # GET /entries/impact
  #
  # THE §6 CARD FOR A CATEGORY THE USER HAS JUST PICKED. The envelope is derived from the category
  # (§6: "derived, never picked"), so every category change asks the server what the card now says
  # — and it is the server that says it, because every branch the card has is a server decision.
  #
  # READ-ONLY, AND THE ONLY THING ON THIS CONTROLLER THAT IS GUARANTEED TO STAY THAT WAY. It renders
  # a presenter that writes nothing, so `Σ pools == your bank balance` is untouched by construction
  # rather than by care.
  #
  # `find_by` and not `find` on both scalars: the category select can be CLEARED, which asks this
  # action for the card of no category at all, and the honest answer is an empty fragment rather
  # than a 404 in the console. Both are scoped to `current_user` — a card is a report of somebody's
  # balance, and an unscoped `Entry.find` here would report a stranger's.
  def impact
    render partial: "entries/impact",
           locals: {
             impact: EntryImpactPresenter.new(
               user: current_user,
               category: current_user.categories.find_by(id: params[:category_id]),
               amount: params[:amount],
               entry: current_user.entries.find_by(id: params[:entry_id])
             )
           }
  end

  # DELETE /entries/1
  def destroy
    @entry.destroy
    redirect_to entries_path, notice: "Entry was successfully deleted."
  end

  private

  # THE §6 CARD FOR THE FORM AS IT STANDS. A helper method rather than an instance variable set in
  # a filter, because `create` and `update` build their entry INSIDE the action: a `before_action`
  # would have nothing to read and an `after_action` runs after the render it is meant to feed.
  # Asked once, by the form, at the moment it renders.
  #
  # `entry.amount` is what the form is currently showing — the entry's own on edit, the rejected
  # figure on a failed submit — so the card opens on the truth for the amount beside it rather than
  # on a blank-slate figure the browser has to correct.
  #
  # Memoised because the form asks twice — once for the card and once for the submit button's
  # label — and the answer involves a pool's five ledger aggregates.
  def entry_impact(entry)
    @entry_impact ||= EntryImpactPresenter.new(
      user: current_user,
      category: entry.item&.category,
      amount: entry.amount,
      entry: entry.persisted? ? entry : nil
    )
  end

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
    @categories = current_user.categories.order(:category_type, :name)
  end

  def entry_params
    params.expect(entry: [:amount, :date, :description, :item_id]).tap do |permitted_params|
      permitted_params[:amount] = evaluate_formula(permitted_params[:amount])

      # If item_id is not a valid UUID (e.g. name of new item from TomSelect), treat it as blank
      permitted_params[:item_id] = nil if permitted_params[:item_id].present? && !permitted_params[:item_id].match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)

      permitted_params[:item_attributes] = item_attributes if permitted_params[:item_id].blank? && params.dig(:entry, :item_attributes, :name).present?
    end
  end

  def evaluate_formula(raw)
    return raw if raw.blank?
    result = Dentaku::Calculator.new.evaluate(raw.to_s)
    result.is_a?(Numeric) ? result : raw
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
