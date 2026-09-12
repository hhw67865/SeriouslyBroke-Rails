# frozen_string_literal: true

require "rails_helper"

# COMING UP — every dated rule due in the next 30 days, with where its money stands. The grid is
# biweekly anchored 2026-02-06, so the period containing Sep 9 is Sep 4 – Sep 17.
RSpec.describe "Home coming up", type: :system do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user, :biweekly) }
  let(:today) { Date.new(2026, 9, 9) }

  before do
    create(:account, user: user, name: "Checking", opening_balance: 5_000)
    sign_in user, scope: :user
  end

  def dated(name, amount, due, starts_on:)
    create(
      :rule,
      :bill,
      amount: amount,
      anchor_date: due,
      starts_on: starts_on,
      category: create(:category, user: user, name: name)
    )
  end

  def rule_for(name, rate:)
    create(
      :rule,
      :rate,
      amount: rate,
      category: create(:category, user: user, name: name),
      starts_on: Date.new(2026, 1, 1)
    )
  end

  def spend(category, amount, on: today) = create(:entry, item: create(:item, category: category), amount: amount, date: on)

  def read_home = travel_to(today) { visit root_path }

  # Rent: started Sep 4, the same period the Sep 12 due date falls in, so a bill due within its own
  # starting period is fully planned in that one period regardless of how early in it starts_on
  # sits — ClaimCalculator#planned_for divides the gap by `periods_left_from`, which is clamped to a
  # minimum of 1 and is exactly 1 here. Starting Rent earlier does not produce a shortfall; only
  # spending in its lane does, by eating into what was already set aside — so the fixture spends
  # $200 in Rent's category rather than moving `starts_on`.
  def seed_upcoming!
    dated("Dentist", 300, Date.new(2026, 9, 12), starts_on: Date.new(2026, 8, 1))
    dated("Vet", 180, Date.new(2026, 10, 1), starts_on: Date.new(2026, 9, 4))
    dated("Insurance", 1_200, Date.new(2026, 12, 1), starts_on: Date.new(2026, 9, 4))
    rent = dated("Rent", 900, Date.new(2026, 9, 12), starts_on: Date.new(2026, 9, 4))
    spend(rent.category, 200, on: Date.new(2026, 9, 6))
  end

  it "lists what is due within 30 days, soonest first, with its state", :aggregate_failures do
    seed_upcoming!

    read_home

    within("[data-upcoming]") do
      expect(all("[data-upcoming-row]").pluck("data-upcoming-row")).to eq(["Dentist", "Rent", "Vet"])
      expect(page).to have_css("[data-upcoming-row='Dentist'][data-upcoming-state='ready']", text: "Ready — it's all there")
      expect(page).to have_css("[data-upcoming-row='Rent'][data-upcoming-state='short']", text: "short")
      expect(page).to have_css("[data-upcoming-row='Vet'][data-upcoming-state='building']", text: "set aside")
      expect(page).to have_no_css("[data-upcoming-row='Insurance']")
    end
  end

  it "renders nothing when nothing is due" do
    rule_for("Groceries", rate: 400)
    read_home
    expect(page).to have_no_css("[data-upcoming]")
  end
end
