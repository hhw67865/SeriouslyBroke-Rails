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
  #
  # ** AN OPENING ENTRY'S ACCOUNT IS NOT EDITABLE FROM THIS SCREEN (fix round — MED-1). ** The form
  # renders no select for one (see `entries/_form.html.erb`), so the only ways this param arrives on
  # an opening entry are a stale page and a crafted POST — and both used to be accepted.
  # `#sync_income_routing` would call `Entry#route_income_to!`, which rewrites the entry's transfer,
  # and that transfer is HALF the record of what an account holds: re-pointing Ally's opening at HYSA
  # left Ally correcting against a movement that had walked away (measured: Ally corrected to $1,000
  # afterwards showed $500, and HYSA silently gained then lost the same $500).
  #
  # ** AND ITS AMOUNT IS NOT EDITABLE HERE EITHER (fix round round 2 — item 1). ** The amount IS the
  # opening record: changing it has to recompute the account's transfer, and `AccountOpening` is the
  # one object that does that. Two failures came through this door before the refusal:
  #
  #   * `amount: 0` passed `Entry`'s own validation (zero is legal for an opening row) and then
  #     `#sync_income_routing` tried to mirror it — `AccountMovement`'s `amount > 0` CHECK raised a
  #     500 AFTER `route_income_to!`'s `destroy_all` had already removed the real movement, leaving
  #     the account holding money nothing had moved.
  #   * any other figure rewrote the entry and left the movement on the OLD one, so the account read
  #     one number and the ledger another.
  #
  # ** AND ITS ITEM IS NOT EDITABLE EITHER, WHICH IS THE SAME RULE ABOUT THE SAME ROW (fix round 3 —
  # R3). ** An entry's item names its CATEGORY, and the category's type is the SIGN of the money: a
  # crafted `item_id` pointing at an expense item turned a $500 opening INCOME entry into a $500
  # expense — a $1,000 swing in `income − expenses` — while the transfer beside it still moved $500
  # into the account. The invariant broke, and the account's card went on reading "answered" over a
  # record that now said the opposite of what it had. The category cannot be changed without the
  # item, so guarding the item guards both.
  #
  # ONE DOOR, and it is the account's own card. The DATE and the DESCRIPTION are still editable here
  # — neither is part of the arithmetic — and a save that changes NONE of the three (the ordinary "I
  # opened the form and pressed Save") goes through untouched.
  #
  # REFUSED RATHER THAN IGNORED, and 422 rather than a redirect: a request that asked for something
  # the app will not do should say so where the user is standing, with the same sentence the form
  # prints in place of the select.
  def update
    return refuse_reopening if @entry.opening? && (@routing_asked || amount_edited? || item_edited?)

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

  # ** THE EXPENSES TAB IS ABOUT SPENDING, AND AN OPENING RECORD IS NOT SPENDING (fix round —
  # MED-2). ** `Opening Shortfall` is an EXPENSE category by construction — that is how a negative
  # opening lowers the pot — so a household filtering their ledger for what they spent met a $400
  # row that is the record of what an account started with.
  #
  # BY THE MARKER COLUMN, NOT BY `Category.spendable`: the question on this screen is about a ROW,
  # and `entries.opening_account_id` answers it exactly, whichever of the two opening categories the
  # row happens to sit in.
  #
  # THE `all` TAB STILL LISTS IT, deliberately and load-bearing: an opening entry is an ordinary
  # entry a user may delete, and deleting it puts the question back on the account's card
  # (`HomePresenter#awaiting_opening?`). A filter that hid it from every tab would hide the door.
  def apply_type_filter(entries)
    case params[:type]
    when "expenses"
      entries.spendable
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
  # ** AN OPENING ENTRY IS SKIPPED OUTRIGHT (fix round round 2 — item 1), AND THAT IS THE HALF THE
  # 422 ABOVE CANNOT COVER. ** Its transfer is owned by `AccountOpening`, which writes it in the
  # direction the SIGN demands: main → account for money the user has, account → main for an account
  # stated below what the app has moved into it. This method knows only the income direction, so on a
  # negative opening — an entry in the EXPENSE-typed `Opening Shortfall` category — the first line
  # below fired `route_income_to!(nil)` and silently deleted the account → main movement on any save
  # of that form, including one that changed nothing but the description.
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
    return if @entry.opening?
    return @entry.route_income_to!(nil) unless @entry.category.income?

    @entry.route_income_to!(@routing_asked ? @destination_account : @entry.routed_account)
  end

  # THE 422 THAT SAYS WHY, IN THE FORM'S OWN WORDS (`Entry#opening_refusal` is the one spelling).
  # Nothing is written: the entry is re-rendered exactly as it stands, so the amount, the date and
  # the account it actually belongs to are all still true on the screen the user is looking at.
  # ** THE FIGURE AS SUBMITTED AGAINST THE FIGURE AS STORED. ** An UNCHANGED save is not an edit and
  # must go through (that is the ordinary "open the form, press Save"), so the test is a comparison
  # rather than the param's presence. `exception: false` because a blank or unparsable amount is a
  # request the form would never make, and "cannot be read" is a change like any other here — the
  # refusal is the honest answer rather than a 500 out of BigDecimal().
  def amount_edited?
    submitted = params.dig(:entry, :amount)
    return false if submitted.blank?

    BigDecimal(submitted.to_s, exception: false)&.round(2) != @entry.amount
  end

  # THE ITEM AS SUBMITTED AGAINST THE ITEM AS STORED, on the same "an unchanged save is not an edit"
  # rule as `#amount_edited?`. The opening form submits no `item_id` at all, so a value arriving here
  # is a stale page or a crafted request either way.
  def item_edited?
    submitted = params.dig(:entry, :item_id)

    submitted.present? && submitted != @entry.item_id
  end

  def refuse_reopening
    flash.now[:alert] = @entry.opening_refusal
    render :edit, status: :unprocessable_content
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

  # WHICH ACCOUNT THE "Lands in" SELECT IS SET TO. Three sources, in the order that keeps a form
  # honest about what the user last said: the destination THIS request carried (so a re-rendered
  # form still holds the account they picked rather than resetting to main), then where the entry
  # is actually routed, then the user's main account — which is what "no routing movement" means.
  #
  # This is the VALUE only. Whether the field is visible is `_form`'s own question and a rejected
  # create gets that one wrong — see the note there on `build_item`.
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
