# frozen_string_literal: true

# The entry form's params onto an entry: a formula in the amount, an item by id or by a new name
# in the given category.
class EntryForm
  UUID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/i

  attr_reader :user, :entry

  def initialize(user, entry, params, category_id: nil)
    @user = user
    @entry = entry
    @params = params.to_h.deep_symbolize_keys
    @category_id = category_id
    apply
  end

  delegate :save, :errors, to: :entry

  private

  def apply
    entry.amount = evaluate(@params[:amount]) if @params.key?(:amount)
    entry.date = @params[:date] if @params.key?(:date)
    entry.description = @params[:description] if @params.key?(:description)
    assign_item
  end

  def assign_item
    id = @params[:item_id].to_s
    name = @params.dig(:item_attributes, :name).to_s.strip
    if id.match?(UUID)
      entry.item = user.items.find(id)
    elsif name.present? && @category_id.present?
      entry.item = find_or_build_item(name)
    end
  end

  def find_or_build_item(name)
    category = user.categories.find(@category_id)
    category.items.find_by("LOWER(name) = ?", name.downcase) || category.items.build(name: name)
  end

  def evaluate(raw)
    return raw if raw.blank?

    result = Dentaku::Calculator.new.evaluate(raw.to_s)
    result.is_a?(Numeric) ? result : raw
  end
end
