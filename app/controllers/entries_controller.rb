# frozen_string_literal: true

class EntriesController < ApplicationController
  include Searchable

  before_action :set_entry, only: [:edit, :update, :destroy]
  before_action :load_options, only: [:new, :edit, :create, :update]
  before_action :set_previous_url, only: [:new, :create, :edit, :update]

  helper_method :entry_impact

  def index
    @entries = build_entries_query
    @current_type = params[:type] || "all"
    @current_sort = params[:sort]
    @current_direction = params[:direction] == "desc" ? "desc" : "asc"
    @search_state = current_search_state(params)
  end

  def new
    item = current_user.items.find_by(id: params[:item_id])
    @entry = Entry.new(item: item)
    prefill_from(item)
    @usual = UsualItems.new(current_user, today: current_user.today).rows
  end

  def edit; end

  def create
    @entry = Entry.new
    write(:new, "Entry was successfully created.")
  end

  def update
    write(:edit, "Entry was successfully updated.")
  end

  def destroy
    @entry.destroy
    redirect_to(params[:return] == "activity" ? activity_path : entries_path, notice: "Entry was successfully deleted.")
  end

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

  private

  def write(template, notice)
    form = EntryForm.new(current_user, @entry, entry_params, category_id: params[:category_id])
    if form.save
      redirect_to previous_path, notice: notice
    else
      render template, status: :unprocessable_content
    end
  end

  def entry_impact(entry)
    @entry_impact ||= {}
    @entry_impact[entry] ||= EntryImpactPresenter.new(
      user: current_user, category: entry.item&.category, amount: entry.amount, entry: entry.persisted? ? entry : nil
    )
  end

  def build_entries_query
    entries = current_user.entries.includes(item: :category)
    entries = apply_type_filter(entries)
    entries = apply_search(entries, { q: params[:q], field: params[:field] })
    apply_sorting(entries).page(params[:page])
  end

  def apply_type_filter(entries)
    case params[:type]
    when "expenses" then entries.expenses
    when "income" then entries.incomes
    else entries
    end
  end

  def apply_sorting(entries)
    direction = params[:direction] == "desc" ? "desc" : "asc"
    case params[:sort]
    when "date" then entries.order(date: direction)
    when "amount" then entries.order(amount: direction)
    else entries.order(date: :desc)
    end
  end

  def set_entry = @entry = current_user.entries.find(params[:id])

  # Fills the new entry from the item's last entry, so tapping a usual chip changes nothing on
  # screen until Create Entry. The date stays today's — the form already defaults that itself.
  def prefill_from(item)
    @prefilled_from = item&.last_entry
    return unless @prefilled_from

    @entry.assign_attributes(amount: @prefilled_from.amount, description: @prefilled_from.description)
  end

  def load_options
    @categories = current_user.categories.order(:category_type, :name)
  end

  def entry_params
    params.expect(entry: [:amount, :date, :description, :item_id, { item_attributes: [:name] }])
  end

  def set_previous_url
    @previous_url = params[:previous_url]
    return unless @previous_url.blank? && request.referer.present? && URI(request.referer).path != new_entry_path

    @previous_url = request.referer
  end

  def previous_path
    return calendar_week_path(date: @entry.date) if @previous_url.present? && @previous_url.include?("calendar")

    @previous_url || entries_path
  end
end
