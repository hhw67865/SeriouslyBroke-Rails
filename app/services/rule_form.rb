# frozen_string_literal: true

# The rule form's words, turned into a rule's columns. Two schedules: per period (which may keep
# what it doesn't spend) and by a date (which may repeat every N months).
class RuleForm
  include ActiveModel::Model

  SCHEDULES = ["per_period", "by_date"].freeze
  DEFAULT_SCHEDULE = "per_period"
  FIELDS = [:category_id, :item_id, :new_item_name, :rule_type, :amount, :schedule, :repeats, :keeps, :interval_months, :anchor_date, :starts_on].freeze
  RULE_ERROR_FIELDS = {
    interval_months: :schedule,
    anchor_date: :schedule,
    amount: :amount,
    rule_type: :rule_type,
    item: :item_id,
    category: :category_id,
    starts_on: :starts_on
  }.freeze

  attr_reader :user, :rule, :anchor_date, :starts_on
  attr_accessor :category_id, :item_id, :new_item_name, :rule_type, :amount, :schedule, :interval_months
  attr_writer :repeats, :keeps

  def initialize(user, params = {}, rule: nil)
    @user = user
    @rule = rule || Rule.new
    assign(params)
    apply_to_rule
  end

  def self.from(rule)
    schedule = rule.anchor_date.present? ? "by_date" : "per_period"
    {
      category_id: rule.category_id,
      item_id: rule.item_id,
      rule_type: rule.rule_type,
      amount: rule.amount,
      schedule: schedule,
      repeats: schedule == "by_date" && rule.interval_months.present?,
      keeps: rule.keeps_unspent,
      interval_months: rule.interval_months,
      anchor_date: rule.anchor_date,
      starts_on: rule.starts_on
    }
  end

  def save
    return false unless choices_are_coherent? && new_item_ready?

    rule.save.tap { |written| carry_rule_errors unless written }
  end

  delegate :persisted?, to: :rule

  def repeats = ActiveModel::Type::Boolean.new.cast(@repeats)
  def repeats? = repeats.present?
  def keeps = ActiveModel::Type::Boolean.new.cast(@keeps)
  def keeps? = keeps.present? && schedule != "by_date"

  def anchor_date=(value)
    @anchor_date = Rule.type_for_attribute(:anchor_date).cast(value)
  end

  def starts_on=(value)
    @starts_on = Rule.type_for_attribute(:starts_on).cast(value)
  end

  private

  def assign(params)
    params = params.to_h.symbolize_keys
    FIELDS.each { |field| public_send(:"#{field}=", params[field]) if params.key?(field) }
    @schedule = @schedule.presence&.to_s || DEFAULT_SCHEDULE
    @rule_type = @rule_type.presence&.to_s
    self.starts_on = default_starts_on if starts_on.blank?
  end

  def default_starts_on
    rule.starts_on || user.today
  end

  def apply_to_rule
    rule.assign_attributes(category_id: category_id.presence, amount: amount, starts_on: starts_on, **schedule_columns)
    assign_item
    rule.rule_type = rule_type if rule_type_known?
  end

  # A new item is unsaved, so rule.item_id stays nil until the rule (and it) are saved.
  def assign_item
    if item_id == "new"
      rule.item = rule.category&.items&.build(name: new_item_name)
    else
      rule.item_id = item_id.presence
    end
  end

  def schedule_columns
    return { anchor_date: nil, interval_months: nil, keeps_unspent: keeps? } unless schedule == "by_date"

    { anchor_date: anchor_date, interval_months: (interval_months.presence if repeats?), keeps_unspent: false }
  end

  def rule_type_known? = rule_type.blank? || Rule.rule_types.key?(rule_type)

  # A new item's own errors (chiefly its uniqueness) land on :item_id, the field it stands in for.
  def new_item_ready?
    return true unless item_id == "new"
    return false unless new_item_named?
    return true if rule.item&.valid?

    surface_new_item_errors
    false
  end

  def new_item_named?
    return true if new_item_name.present?

    errors.add(:item_id, "needs a name for the new item")
    false
  end

  def surface_new_item_errors
    return errors.add(:item_id, "needs a category before it can be named") if rule.item.blank?

    rule.item.errors.each { |error| errors.add(:item_id, error.message) }
  end

  def choices_are_coherent?
    errors.clear
    errors.add(:schedule, "is not one of the choices on this form") unless SCHEDULES.include?(schedule)
    errors.add(:rule_type, "is not a kind of rule") unless rule_type_known?
    check_schedule_fields if SCHEDULES.include?(schedule)
    errors.empty?
  end

  def check_schedule_fields
    if schedule == "by_date"
      errors.add(:schedule, "needs the date it is first due") if anchor_date.blank?
      errors.add(:schedule, "needs the number of months it comes round in") if repeats? && interval_months.blank?
    else
      errors.add(:schedule, "does not take a due date — choose \"By a date\" for a dated rule") if anchor_date.present?
      errors.add(:schedule, "does not take a number of months — tick \"repeats\" to set one") if interval_months.present?
    end
  end

  def carry_rule_errors
    rule.errors.each { |error| errors.add(form_field_for(error), error.message) }
  end

  def form_field_for(error)
    return :item_id if error.attribute == :base && error.message == Rule::CATCH_ALL_TAKEN

    RULE_ERROR_FIELDS.fetch(error.attribute, error.attribute)
  end
end
