# frozen_string_literal: true

require "rails_helper"

# The distribution screen's proposal. Overrides (Task 5) and confirming (Task 6) are not here
# yet, so every example below is about what the screen SAYS.
#
# `Capybara.exact` is unset, so a bare `have_content("$400.00")` also matches "$1,400.00" and
# matches anything the sidebar happens to print. Every figure below is therefore scoped — to the
# sources list, to the buffer line, or to the row that owns it.
RSpec.describe "Distributions Proposal", type: :system do
  # Biweekly, anchored today, so this period is today..+13 and the one before it ended
  # yesterday. Money paid in a fortnight ago therefore belongs to a period that has closed —
  # which is what makes Groceries' $85 sweepable.
  let(:user) { create(:user, period_cadence: :biweekly, period_anchor_date: Date.current) }
  let(:checking) { create(:pool, :account, user: user, name: "Checking") }

  before { sign_in user, scope: :user }

  # THE worked example, and the figures are all independent: $500 arrived last period and $85 of
  # it went out to Groceries, leaving $415 carried over; $2,400 landed this period; the $85 comes
  # back. $400 + $2,600 + $150 of asks then drain the $2,900 and run out inside Car.
  describe "a short distribution", :aggregate_failures do
    before do
      envelope("Groceries", 400, funded: 85, priority: 1)
      envelope("Car", 2_600, priority: 2)
      envelope("Vacation", 150, priority: 3)
      deposit(500, on: Date.current - 14)
      deposit(2_400, on: Date.current)
      visit new_distribution_path
    end

    it "headlines the total and breaks it into where it came from" do
      expect(page).to have_css("h2", text: "Distribute $2,900.00")

      within("#distribution-sources") do
        expect(page).to have_content("Buffer carried over $415.00", normalize_ws: true)
        expect(page).to have_content("Income this period $2,400.00", normalize_ws: true)
        expect(page).to have_content("Swept back from Groceries $85.00", normalize_ws: true)
        expect(page).to have_content("Available $2,900.00", normalize_ws: true)
        # Nothing left this account inside the period, so the residual line has no cause and does
        # not render. Paired with the overdrawn example below, where it does.
        expect(page).to have_no_content("Spent and moved this period")
      end
    end

    # The density switch, half one. The waterfall renders in full, every row of it — including
    # the envelope that got nothing, which is the row a collapsed screen would quietly starve.
    it "shows every row, and where the money ran out" do
      expect(page).to have_css("#distribution-waterfall")
      expect(page).to have_content("$250.00 of what your envelopes asked for isn't there")

      # A FULLY funded row prints the bare amount — `$400.00`, never `$400.00 of $400.00`, which
      # is the noise the helper drops. `Capybara.exact` is unset, so the positive assertion alone
      # passes on either string; the pairing is what pins which one was rendered.
      within("[data-pool-name='Groceries']") do
        expect(page).to have_content("$400.00")
        expect(page).to have_no_content(" of ")
      end
      within("[data-pool-name='Car']") { expect(page).to have_content("$2,500.00 of $2,600.00") }
      within("[data-pool-name='Vacation']") { expect(page).to have_content("$0.00 of $150.00") }
      expect(page).to have_content("ran out here · $250.00 unfunded")
    end

    # The one-line summary belongs to the all-clear density and must not appear here. Paired with
    # the positive assertion above it — a summary line that was never rendered under any
    # condition would pass the absence on its own.
    it "does not collapse to the all-clear summary" do
      expect(page).to have_css("#distribution-waterfall")
      expect(page).to have_no_css("#distribution-summary")
    end

    # Where the swept money physically was, said on the row it came out of as well as in the
    # breakdown — and `· last period` is the marker that explains why it is being taken back.
    it "marks the envelope whose period has closed" do
      within("[data-pool-name='Groceries']") do
        expect(page).to have_content("last period")
        expect(page).to have_content("$85.00 swept back")
      end
      within("[data-pool-name='Car']") { expect(page).to have_no_content("swept back") }
    end

    # Two moments, not one level: the buffer had $415 before this period's income and ends the
    # distribution with nothing, which is the sentence a slow bleed shows up in.
    it "states the buffer before and after" do
      within("#distribution-buffer") { expect(page).to have_content("$415.00 → $0.00", normalize_ws: true) }
    end
  end

  # The other half of the density switch, on the same fixture with one ask changed. A screen
  # that rendered the table unconditionally would pass every example above.
  describe "an all-clear distribution", :aggregate_failures do
    before do
      envelope("Groceries", 400, funded: 85, priority: 1)
      envelope("Car", 100, priority: 2)
      envelope("Vacation", 150, priority: 3)
      checking.update!(target_amount: 4_000)
      deposit(500, on: Date.current - 14)
      deposit(2_400, on: Date.current)
      visit new_distribution_path
    end

    it "says it in one line instead of a table" do
      expect(page).to have_css("h2", text: "Distribute $2,900.00")

      within("#distribution-summary") do
        expect(page).to have_content("3 envelopes funded in full, $650.00 out", normalize_ws: true)
        expect(page).to have_content("$2,250.00 stays in your buffer · you wanted $4,000.00", normalize_ws: true)
      end

      expect(page).to have_no_css("#distribution-waterfall")
      # The rows are what the table would have shown, so their absence is the switch actually
      # having fired rather than a heading that moved.
      expect(page).to have_no_css("[data-pool-name='Car']")
    end

    # The breakdown answers "where did this number come from" on both densities — it is the
    # headline's provenance, not part of the table.
    it "still shows where the money came from" do
      within("#distribution-sources") { expect(page).to have_content("Income this period $2,400.00", normalize_ws: true) }
    end
  end

  # Spec §5: "anything short OR OVERDUE → the full waterfall". The overdue half is the one the
  # short-only switch could not reach — this envelope already holds its $120, so it asks for
  # nothing and has no row at all, and the screen used to collapse to "2 envelopes funded in full"
  # over a bill that is already late.
  describe "an all-clear distribution with an overdue bill", :aggregate_failures do
    before do
      envelope("Groceries", 400, priority: 1)
      overdue_envelope("Utilities", 120, funded: 120, priority: 2)
      deposit(2_400, on: Date.current)
      visit new_distribution_path
    end

    it "opens the full table and says what needs you" do
      expect(page).to have_css("#distribution-waterfall")
      expect(page).to have_no_css("#distribution-summary")
      expect(page).to have_content("Every envelope gets what it asked for, but something below still needs you")

      within("[data-alert-pool='Utilities']") do
        expect(page).to have_content("overdue · was #{(Date.current - 10).strftime("%b %-d")}")
        expect(page).to have_content("Its money is already there")
      end
    end

    # Nothing ran out, so the cutoff must not be drawn. It is keyed off the row funding, which
    # finds nothing here and falls back to the end of the list — the line would read
    # "ran out here · $0.00 unfunded" on a screen where every envelope was funded in full.
    it "draws no cutoff on a period that never ran out" do
      expect(page).to have_css("[data-pool-name='Groceries']")
      expect(page).to have_no_content("ran out here")
    end
  end

  # The row half of the same rule, and the pairing DistributionsHelper::DATED_STATES exists for:
  # `overdue` prints the date of the rule that made it late, so the schedule clause — which
  # describes the earliest-due rule, not necessarily the same one — must stay off. Asserted
  # against the "4 periods left" row above, which is the same helper printing the clause.
  describe "an overdue bill that still needs money", :aggregate_failures do
    before do
      overdue_envelope("Utilities", 120, priority: 1)
      deposit(2_400, on: Date.current)
      visit new_distribution_path
    end

    it "prints one date on the row and no schedule clause" do
      within("[data-pool-name='Utilities']") do
        expect(page).to have_content("overdue · was #{(Date.current - 10).strftime("%b %-d")}")
        expect(page).to have_no_content("periods left")
        expect(page).to have_no_content("due #{(Date.current - 10).strftime("%b %-d")}")
      end
    end
  end

  # Amendment B. One account has no sibling overdraft to cancel against, so the negative is real
  # and the screen says so rather than flooring it at zero.
  describe "an overdrawn account", :aggregate_failures do
    before do
      envelope("Groceries", 400, priority: 1)
      deposit(100, on: Date.current)
      spend(300, on: Date.current)
      visit new_distribution_path
    end

    it "prints the negative rather than a zero" do
      expect(page).to have_css("h2", text: "Nothing to distribute")
      expect(page).to have_content("Checking is $200.00 in the red")

      within("#distribution-sources") do
        # The overdraft is the SPENDING line's, not the carried-over line's: this account opened
        # the period holding nothing, took $100 in and paid $300 out.
        expect(page).to have_content("Buffer carried over $0.00", normalize_ws: true)
        expect(page).to have_content("Spent and moved this period -$300.00", normalize_ws: true)
        expect(page).to have_content("Available -$200.00", normalize_ws: true)
      end
      within("#distribution-buffer") { expect(page).to have_content("$0.00 → -$200.00", normalize_ws: true) }
      within("[data-pool-name='Groceries']") { expect(page).to have_content("$0.00 of $400.00") }
    end
  end

  # A row's schedule comes from ONE rule, so its date and its count cannot describe two different
  # bills. $1,200 due in 43 days, biweekly from a boundary that is today: today, +14, +28 and +42
  # all fall on or before it, so four periods remain and the ask is $300 — the amount is what
  # makes the count checkable rather than decorative, since a different count moves it.
  describe "an envelope funding a dated bill", :aggregate_failures do
    let(:due_on) { Date.current + 43 }

    before do
      pool = create(:pool, :budget_pool, user: user, account: checking, name: "Rent", priority: 1)
      create(:pool_budget, pool: pool, amount: 1_200, interval_months: 12, anchor_date: due_on)
      deposit(100, on: Date.current)
      visit new_distribution_path
    end

    it "says when the bill lands and how many periods are left to fund it" do
      within("[data-pool-name='Rent']") do
        expect(page).to have_content("due #{due_on.strftime("%b %-d")} · 4 periods left", normalize_ws: true)
        expect(page).to have_content("$100.00 of $300.00")
      end
    end
  end

  # Confirming REPLACES this period's split rather than adding to it, so the screen shows the
  # period as if that split had never happened — and says so, because a user who cannot see what
  # is about to be discarded cannot consent to discarding it.
  describe "a period that has already been distributed", :aggregate_failures do
    before do
      envelope("Groceries", 400, funded: 85, priority: 1)
      envelope("Car", 2_600, priority: 2)
      deposit(500, on: Date.current - 14)
      deposit(2_400, on: Date.current)
      AllocationCommitter.new(
        AllocationCalculator.new(user: user, account: checking, today: Date.current)
      ).call
      visit new_distribution_path
    end

    it "proposes the same split again and labels it as a replacement" do
      expect(page).to have_content("You've already distributed this period")
      expect(page).to have_content("3 movements, $2,985.00 moved", normalize_ws: true)

      expect(page).to have_css("h2", text: "Distribute $2,900.00")
      within("#distribution-sources") { expect(page).to have_content("Swept back from Groceries $85.00", normalize_ws: true) }
      within("[data-pool-name='Groceries']") do
        expect(page).to have_content("$400.00")
        expect(page).to have_no_content(" of ")
      end
      within("[data-pool-name='Car']") { expect(page).to have_content("$2,500.00 of $2,600.00") }
    end

    # Rendering must not move money. The banner above is a claim about a split that has to still
    # be there after the page has been looked at.
    it "leaves the committed split in the ledger" do
      # Waits for the render to finish before reading the ledger — the assertions below are
      # about what the request DID, so they have to run after it did it, and an example that
      # makes no Capybara call at all returns while the page is still loading (measured: this
      # one, reproducibly killing the browser mid-navigation in teardown).
      expect(page).to have_css("#distribution-waterfall")

      expect(PoolMovement.distributed.count).to eq(3)
      expect(PoolMovement.distributed.sum(:amount)).to eq(2_985)
    end
  end

  # A period with no distribution says nothing about replacing one — the opposite direction of
  # the banner, on a screen that otherwise looks the same.
  it "does not call a first distribution a replacement", :aggregate_failures do
    envelope("Groceries", 400, priority: 1)
    deposit(2_400, on: Date.current)

    visit new_distribution_path

    expect(page).to have_css("h2", text: "Distribute $2,400.00")
    expect(page).to have_no_content("You've already distributed this period")
  end

  private

  def envelope(name, rate, funded: nil, priority: 0)
    pool = create(:pool, :budget_pool, user: user, account: checking, name: name, priority: priority)
    create(:pool_budget, :per_paycheck_rate, pool: pool, amount: rate)
    create(:pool_movement, from_pool: checking, to_pool: pool, amount: funded, date: Date.current - 14) if funded
    pool
  end

  # A bill whose date has passed with no payment recorded against its item. The ITEM is what makes
  # a rule payable and therefore what makes it late.
  def overdue_envelope(name, amount, funded: nil, priority: 0)
    pool = create(:pool, :budget_pool, user: user, account: checking, name: name, priority: priority)
    category = create(:category, :expense, user: user, pool: pool)
    create(
      :pool_budget,
      pool: pool,
      item: create(:item, category: category),
      amount: amount,
      interval_months: nil,
      anchor_date: Date.current - 10
    )
    create(:pool_movement, from_pool: checking, to_pool: pool, amount: funded, date: Date.current) if funded
    pool
  end

  def deposit(amount, on:)
    category = create(:category, :income, user: user, pool: checking)
    create(:entry, item: create(:item, category: category), amount: amount, date: on)
  end

  def spend(amount, on:)
    category = create(:category, :expense, user: user, pool: checking)
    create(:entry, item: create(:item, category: category), amount: amount, date: on)
  end
end
