# frozen_string_literal: true

# The cuts dialled on the sacrifice page, written to the rules they came from. A cut is refused,
# and nothing is written, when the rule is fixed, the typed figure is not a positive number, or it
# does not undercut the rule's own claim.
class SacrificeCuts
  include ActiveModel::Model

  attr_reader :user, :today, :count

  def initialize(user, cuts:, today: user.today)
    @user = user
    @today = today
    @cuts = cuts.to_h
    @count = 0
  end

  def apply
    return false if nothing_ticked?

    written = false
    ActiveRecord::Base.transaction do
      lines = @cuts.map { |rule_id, typed| line_for(rule_id, typed) }
      raise ActiveRecord::Rollback if errors.any?

      lines.each { |line| line.fetch(:rule).update!(amount: line.fetch(:amount)) }
      @count = lines.size
      written = true
    end
    written
  end

  private

  def nothing_ticked?
    return false if @cuts.any?

    errors.add(:base, "Tick a rule to cut it first")
    true
  end

  def line_for(rule_id, typed)
    rule = Rule.for_user(user).find(rule_id)
    claim = rule.steady_ask(today: today)
    return { rule: rule, amount: nil } unless check?(rule, claim, typed)

    { rule: rule, amount: (typed.to_s.to_d * rule.amount / claim).round(2) }
  end

  def check?(rule, claim, typed)
    if rule.cadence == :every_n
      errors.add(:base, "#{name_for(rule)} is a fixed bill — it can only be edited on its own form")
    elsif !positive_number?(typed)
      errors.add(:base, "#{name_for(rule)}'s cut needs a positive amount")
    elsif typed.to_s.to_d >= claim
      errors.add(:base, "#{name_for(rule)}'s cut must be below what it asks for now")
    end
    errors.empty?
  end

  def positive_number?(typed) = typed.to_s.strip.match?(/\A\d+(\.\d+)?\z/) && typed.to_s.to_d.positive?
  def name_for(rule) = rule.item&.name || rule.category.name
end
