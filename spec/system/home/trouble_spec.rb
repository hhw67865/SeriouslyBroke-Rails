# frozen_string_literal: true

require "rails_helper"

# THE TROUBLE STRIP — rendered only when something real needs a human. One example per kind, and
# one for the silence, which is the good state. The grid is biweekly anchored 2026-02-06, so the
# period containing Sep 9 is Sep 4 – Sep 17 with eight days left.
RSpec.describe "Home trouble strip", type: :system do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user, :biweekly) }
  let(:today) { Date.new(2026, 9, 9) }
  let!(:checking) { create(:account, user: user, name: "Checking", opening_balance: 1_000) }

  before { sign_in user, scope: :user }

  def category(name) = create(:category, user: user, name: name)

  def envelope(name, rate:, **attributes)
    create(
      :rule,
      :rate,
      amount: rate,
      starts_on: Date.new(2026, 1, 1),
      category: category(name),
      **attributes
    )
  end

  def bill(name, amount:, due:)
    create(
      :rule,
      :bill,
      amount: amount,
      anchor_date: due,
      starts_on: Date.new(2026, 8, 1),
      category: category(name)
    )
  end

  def spend(category, amount, on: today) = create(:entry, item: create(:item, category: category), amount: amount, date: on)

  def read_home = travel_to(today) { visit root_path }

  it "says nothing at all when nothing needs a human", :aggregate_failures do
    envelope("Groceries", rate: 400)

    read_home

    expect(page).to have_no_css("[data-trouble]")
    expect(page).to have_css("[data-free]", text: "$600.00")
  end

  # A NON-MAIN ACCOUNT BELOW ZERO. Main is excluded, because main's overdraft IS the money row's red
  # "In checking" figure. No button: nothing on the purpose side can reach a bank overdraft.
  it "names an overdrawn account and the debt it is", :aggregate_failures do
    ally = create(:account, user: user, name: "Ally")
    create(:transfer, from_account: ally, to_account: checking, amount: 40, date: today)

    read_home

    expect(page).to have_css("[data-overdrawn-account='Ally']", text: "Ally is overdrawn $40.00")
    expect(page).to have_css("[data-trouble] h3", text: "1 thing needs you")
  end

  # FREE BELOW ZERO: the figure, who gives way, what the walk cannot account for, and the pace that
  # lands the period at zero. $1,000 in, $1,100 spent on nothing any rule claims and a $50 claim
  # standing — so the shortfall outlasts the give-way list by $100.
  it "says who gives way, by how much, and what is left over", :aggregate_failures do
    envelope("Fun", rate: 50, rule_type: :choice)
    spend(category("Repairs"), 1_100, on: Date.new(2026, 9, 6))
    create(:account, user: user, name: "Ally", opening_balance: 500)

    read_home

    expect(page).to have_css("[data-shortfall-headline]", text: "Your rules claim $150.00 more than checking holds")
    expect(page).to have_css("[data-shortfall-amount]", text: "short $150.00")
    expect(page).to have_css("[data-shortfall-elsewhere]", text: "$500.00 of your money is sitting outside")
    expect(page).to have_css("[data-shortfall-pace]", text: "Spending $18.75 a day less")
    expect(page).to have_css("[data-uncovered-claim='Fun']", text: "nothing covers its $50.00")
    expect(page).to have_css("[data-uncovered-remainder]", text: "$100.00 past everything the rules claim")
  end

  # SPENT PAST WHAT THE RULE HAD. The excess is the pre-clamp figure: the claim itself is zero here,
  # so a figure taken from the claim would print "over by $0.00" on every overspend.
  it "names a rule spent past what it had", :aggregate_failures do
    rule = envelope("Groceries", rate: 400)
    spend(rule.category, 450)

    read_home

    expect(page).to have_css("[data-problem-category='Groceries']")
    expect(page).to have_css("[data-problem-state]", text: "over by $50.00")
    expect(page).to have_css("[data-problem-detail]", text: "$450.00 spent of $400.00")
    expect(page).to have_css("[data-problem-detail]", text: "the excess comes straight out of what is free")
  end

  # A DATE THAT PASSED WITH THE BILL UNPAID. The trigger is the date, because a bill nobody paid
  # needs a human whether or not the money is there — and the fund state decides the instruction:
  # write the cheque, or find the rest of it first.
  it "names an overdue bill whose money is all there", :aggregate_failures do
    bill("Insurance", amount: 200, due: Date.new(2026, 9, 5))

    read_home

    within("[data-problem-category='Insurance']") do
      expect(page).to have_css("[data-problem-state]", text: "overdue · was Sep 5")
      expect(page).to have_css("[data-problem-detail]", text: "it's all there — pay it and it starts again")
    end
  end

  # The other instruction: find the rest of it before writing the cheque.
  it "names an overdue bill still short of its target" do
    rule = bill("Water", amount: 200, due: Date.new(2026, 9, 5))
    spend(rule.category, 100, on: Date.new(2026, 9, 6))

    read_home

    expect(page).to have_css("[data-problem-detail]", text: "$100.00 built up of $200.00 — $100.00 short — this needs paying")
  end

  # A verdict about the SHAPE of the rules, which no amount of care this period can fix. Aug 21
  # opens the last complete period, so income from that day gives the ledger a period to average.
  it "offers the sacrifice door when the rules outrun typical income", :aggregate_failures do
    envelope("Rent", rate: 5_000, rule_type: :bill)
    create(:entry, :income, user: user, amount: 100, date: Date.new(2026, 8, 21))

    read_home

    expect(page).to have_link("Your budget doesn't fit your income", href: sacrifice_path)
  end
end
