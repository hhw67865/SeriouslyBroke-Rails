# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260907000000_a_fund_keeps_unspent")

# ONE COLUMN COMES BACK, AND NOTHING ELSE MOVES (two-shapes spec §12).
#
# `spec/migrations/two_shapes_spec.rb`'s discipline, asked of a migration with far less to prove:
# this one converts no rows, derives no dates and prints no receipts, so what it owes is exactly
# three things — the column exists with the shape the model relies on, every rule that already
# existed reads `false` rather than NULL, and `down` really removes it so the rewind other specs
# depend on is a true reversal.
#
# ** WHY THE SCHEMA IS REWOUND FOR THE LENGTH OF THIS FILE. ** Its subject is the newest migration,
# so the current schema is the world AFTER it and the `up` under test would meet its own column
# (`PG::DuplicateColumn`). The shared context runs the `down` before the first example and the `up`
# after the last, which is also what proves the `down` correct — and it is why every example below
# calls `migrate!` for itself rather than assuming the column is there.
#
# ** THE DEFAULT IS THE WHOLE DATA MIGRATION. ** Every rule that exists when this runs is a rule
# whose unspent money resets, which is what every screen has been saying about it since `TwoShapes`;
# `false` is therefore the truth about each of them rather than a fallback, and "the claim does not
# move" needs no walk to check — the column is read by nothing that ran before it.
RSpec.describe AFundKeepsUnspent do
  include_context "with the schema its subject was written for", described_class

  let(:migration) { described_class.new }
  let(:connection) { ActiveRecord::Base.connection }
  let(:user) { create(:user, timezone: "UTC") }
  let(:groceries) { create(:category, :expense, :funded, user: user, name: "Groceries") }

  def refresh_columns = [Budget, Category, Entry, Pool, Adjustment].each(&:reset_column_information)

  def migrate!
    migration.suppress_messages { migration.up }
    refresh_columns
  end

  def rewind!
    migration.suppress_messages { migration.down }
    refresh_columns
  end

  def keeps_column = connection.columns(:budgets).find { |column| column.name == "keeps_unspent" }

  # A RULE PLANTED BEFORE THE COLUMN EXISTS, which is the only rule this migration can ever meet.
  # Through the model, because the model is what every other rule in the database was written by —
  # and it validates fine here: `#keeps_unspent_never_dates` is gated on the column's presence
  # exactly so a rewound schema can still plant one.
  def plant_a_rule
    create(:budget, :per_period_rate, category: groceries, amount: 400, rule_type: :usage)
  end

  it "does not have the column before it runs", :aggregate_failures do
    expect(connection.column_exists?(:budgets, :keeps_unspent)).to be(false)
    expect(plant_a_rule).to be_persisted
  end

  # ** THE THREE FACTS THE MODEL RELIES ON. ** `ClaimCalculator#shape` reads the column with no
  # nil-guard at all (`rule.keeps_unspent?`), which is only safe because it is NOT NULL; `RuleForm`
  # writes it on every save of every shape, which is only safe because it takes a boolean; and every
  # rule written before §12 has to read as an allowance that resets, which is the default.
  it "adds a boolean that is NOT NULL and defaults to false", :aggregate_failures do
    migrate!

    expect(connection.column_exists?(:budgets, :keeps_unspent)).to be(true)
    expect(keeps_column.type).to eq(:boolean)
    expect(keeps_column.null).to be(false)
    # THE ADAPTER'S OWN CAST, not the string Postgres stores: `Column#default` comes back already
    # type-cast for a boolean column, and pinning `"false"` here would be pinning the adapter.
    expect(keeps_column.default).to be(false)
  end

  it "reads every rule that already existed as one that does not keep", :aggregate_failures do
    rule = plant_a_rule

    migrate!

    expect(rule.reload.keeps_unspent).to be(false)
    expect(rule.claim_calculator(today: user.today).shape).to eq(:rate)
  end

  # ** AND THE SHAPE IS REACHABLE THE MOMENT THE COLUMN IS. ** The migration is additive, so this is
  # the one example that says what it was FOR: with the column there, the same rule with the box
  # ticked reads `:fund` off the one classifier every screen goes through.
  it "makes the fund shape reachable" do
    migrate!
    fund = create(:budget, :keeps_unspent, category: groceries, amount: 60, rule_type: :usage)

    expect(fund.claim_calculator(today: user.today).shape).to eq(:fund)
  end

  # ** THE ROUND TRIP, WHICH IS WHAT THE REWIND ABOVE DEPENDS ON. ** `down` removes the column
  # outright — nothing is derived from it and no other column is written on the strength of it, so
  # a rule that kept its unspent money becomes the row the database held before §12 — and `up` puts
  # it back on the same terms.
  it "removes the column on the way down and restores it on the way back up", :aggregate_failures do
    migrate!
    create(:budget, :keeps_unspent, category: groceries, amount: 60, rule_type: :usage)

    rewind!
    expect(connection.column_exists?(:budgets, :keeps_unspent)).to be(false)

    migrate!
    expect(connection.column_exists?(:budgets, :keeps_unspent)).to be(true)
    expect(Budget.pluck(:keeps_unspent)).to eq([false])
  end
end
