# frozen_string_literal: true

class EntriesController < ApplicationController
  include Searchable

  before_action :set_entry, only: [:edit, :update, :destroy]
  before_action :set_item, only: [:new, :create]
  before_action :set_destination_account, only: [:create, :update]
  before_action :load_options, only: [:new, :edit, :create, :update]
  before_action :set_previous_url, only: [:new, :create, :edit, :update]

  helper_method :entry_impact, :entry_destination_account

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
      sync_income_routing
      redirect_to previous_path, notice: "Entry was successfully created."
    else
      @entry.build_item
      render :new, status: :unprocessable_content
    end
  end

  # PATCH/PUT /entries/1
  def update
    if @entry.update(entry_params)
      sync_income_routing
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
  #
  # KEYED ON THE ARGUMENT, which a bare `@entry_impact ||=` was not. Its correctness was a fact
  # about the CIRCUMSTANCE rather than about the method: one entry per render today, so the two
  # asks are about the same object and the memo is right by accident. A second entry passed to it
  # in the same request — a form that previewed two rows, an action that rendered a card for the
  # old and the new item — would silently receive the FIRST entry's card, with its balance, its
  # envelope name and its overdraw sentence, beside a different amount. A hash keyed on the entry
  # costs one line and makes the answer a fact about the argument.
  #
  # New records are safe as keys: ActiveRecord leaves `#hash`/`#eql?` on object identity for an
  # unsaved record, so `new` and `create` (which build their entry in the action) get one bucket
  # each rather than colliding on a nil id.
  def entry_impact(entry)
    @entry_impact ||= {}
    @entry_impact[entry] ||= EntryImpactPresenter.new(
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

  # INCOME ROUTING (main-account spec §4) — THE VIRTUAL PARAM, RESOLVED BEFORE THE SAVE.
  #
  # `destination_account_id` is never a column on `entries`, so it is deliberately absent from
  # `entry_params`: it is a question the form asks and #sync_income_routing answers by writing a
  # movement. Resolving it HERE rather than after the save is what keeps a hand-posted stranger's
  # id from leaving a saved entry behind next to its 404.
  #
  # `current_user.pools.pool_type_account.find` — the same scoping law as `categories_controller`,
  # and the type narrowing is half of it: an envelope id is as illegal a destination as another
  # user's account, and `find` says so the same way for both.
  #
  # THE KEY'S PRESENCE IS THE SIGNAL, NOT ITS VALUE (binding resolution). An update posted without
  # the select at all must leave existing routing standing — only somebody who ASKED the question
  # gets to change the answer — while an explicitly blank value means "main", which un-routes.
  def set_destination_account
    @routing_asked = params[:entry].respond_to?(:key?) && params[:entry].key?(:destination_account_id)
    return unless @routing_asked

    id = params[:entry][:destination_account_id]
    @destination_account = current_user.pools.pool_type_account.find(id) if id.present?
  end

  # THE ONE CALLER OF `Entry#route_income_to!`, run after a successful save of either action.
  #
  # An entry that is NOT income clears unconditionally rather than returning early: changing a
  # paycheck's category to Groceries has to take its mirror movement with it, or main would go on
  # paying an envelope for money the app no longer thinks arrived there.
  #
  # `@entry.routed_account` IS THE "NOBODY ASKED" ANSWER, AND IT IS A RE-SYNC RATHER THAN A SKIP:
  # routing to where the entry already routes leaves the destination exactly where it was while
  # re-writing the movement's amount and date from the entry's own, so an edit that only corrects a
  # paycheck from $500 to $750 carries its mirror along. Skipping outright would leave main paying
  # out yesterday's figure forever.
  def sync_income_routing
    return @entry.route_income_to!(nil) unless @entry.category.income?

    @entry.route_income_to!(@routing_asked ? @destination_account : @entry.routed_account)
  end

  def set_item
    @item = current_user.items.find(params[:item_id]) if params[:item_id]
  end

  def load_options
    @categories = current_user.categories.order(:category_type, :name)
    # §4's "Lands in" list. Accounts only — an envelope is not somewhere a paycheck arrives, and
    # #set_destination_account refuses one with the same scope, so the list and the write agree.
    @accounts = current_user.pools.pool_type_account.order(:name)
  end

  # WHERE THE "Lands in" SELECT OPENS. Three sources, in the order that keeps a form honest about
  # what the user last said: the destination THIS request carried (so a rejected create comes back
  # showing the account they picked, not main), then where the entry is actually routed, then the
  # user's main account — which is what "no routing movement" means.
  def entry_destination_account(entry)
    return @destination_account || current_user.default_account if @routing_asked

    (entry.persisted? ? entry.routed_account : nil) || current_user.default_account
  end

  def entry_params
    params.expect(entry: [:amount, :date, :description, :item_id, :destination_account_id]).tap do |permitted_params|
      # PERMITTED, THEN POPPED. `destination_account_id` is not a column on `entries` — it names the
      # account the money ended up in and #sync_income_routing answers it with a MOVEMENT — so mass
      # assignment must never see it. It is permitted all the same because `params.expect` raises
      # ParameterMissing when NONE of its scalars are present, and "change only where this paycheck
      # landed" is a legitimate edit that submits nothing else.
      permitted_params.delete(:destination_account_id)

      # `if key?` AND NOT AN UNCONDITIONAL ASSIGNMENT: `params[:amount] = evaluate_formula(nil)`
      # WRITES the key back as nil, so an update that submits no amount at all — the routing-only
      # edit above is the first one this app can make — mass-assigned `amount: nil` over a saved
      # figure and was rejected by the presence validator. A key the request never sent must stay
      # unsent.
      permitted_params[:amount] = evaluate_formula(permitted_params[:amount]) if permitted_params.key?(:amount)

      normalize_item(permitted_params)
    end
  end

  # TomSelect submits the TYPED NAME of a brand-new item in the same field that otherwise carries an
  # id, so "not a UUID" is this form's way of saying "the user is naming something that doesn't
  # exist yet" — the id is dropped and the name becomes nested attributes instead.
  def normalize_item(permitted_params)
    permitted_params[:item_id] = nil if permitted_params[:item_id].present? && !permitted_params[:item_id].match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)

    permitted_params[:item_attributes] = item_attributes if permitted_params[:item_id].blank? && params.dig(:entry, :item_attributes, :name).present?
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
