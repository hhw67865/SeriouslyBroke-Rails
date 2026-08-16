# frozen_string_literal: true

require "rails_helper"

# Task 5: every waterfall line is editable, and an edit states what it costs you LATER.
#
# `Capybara.exact` is unset, so a bare `have_content("$800.00")` matches "$1,800.00" and matches
# whatever the sidebar prints. Every figure below is scoped to the row, the buffer line or the
# consequence line that owns it.
#
# Every "shows nothing" assertion below is paired with a positive one ON THE SAME SCREEN. A
# consequence partial that was never rendered at all would satisfy the absences on its own, and
# a screen that always printed a line would satisfy the presences on their own — the gate is only
# pinned by having both fire off the same render.
RSpec.describe "Distribution Overrides", type: :system do
  # Biweekly, anchored today: this period is today..+13 and the next one opens on +14. That
  # boundary is what every consequence sentence names, and what makes "periods left" countable.
  let(:user) { create(:user, period_cadence: :biweekly, period_anchor_date: Date.current) }
  let(:checking) { create(:pool, :account, user: user, name: "Checking") }
  let(:next_period) { (Date.current + 14).strftime("%b %-d") }

  before { sign_in user, scope: :user }

  # THE WORKED EXAMPLE, and it is the design spec's own (§5): a $2,000 bill due in 20 days with
  # $1,000 already in the envelope and two periods to go asks $500 a period. Put in $200 and the
  # remaining $800 has one period left to arrive in.
  #
  # $500 carried + $200 income − $1,000 already funded = $700 available; Rent asks $500 and
  # Groceries asks $400, so the money runs out inside Groceries and the table opens.
  describe "a dated bill with two periods left", :aggregate_failures do
    let(:due_on) { Date.current + 20 }

    before do
      dated_envelope("Rent", 2_000, anchor_date: due_on, funded: 1_000, priority: 1)
      rate_envelope("Groceries", 400, priority: 2)
      deposit(1_500, on: Date.current - 14)
      deposit(200, on: Date.current)
      visit new_distribution_path
    end

    # The opposite direction of every consequence example below, taken on the same fixture before
    # anything is typed: the box is there, holding the proposal's own figure, and says nothing.
    it "offers the proposal in the box and says nothing until it is changed" do
      within("[data-pool-name='Rent']") do
        expect(page).to have_field("Amount for Rent", with: "500.00")
        expect(page).to have_content("$500.00")
      end
      expect(page).to have_no_css("[data-consequence]")
    end

    it "names the mechanism, not just the number, when the ask actually changes" do
      fill_in "Amount for Rent", with: "200"
      click_on "Update figures"

      within("[data-consequence='Rent']") do
        # $800, NOT $500 + $300. The two coincide here only because one period remains; the
        # example below with three periods left is the one that tells the two apart.
        expect(page).to have_content(
          "You're moving $300.00 onto your next period. #{next_period} will need $800.00 " \
          "instead of $500.00, the last period before #{due_on.strftime("%b %-d")}.",
          normalize_ws: true
        )
      end
    end

    # The row itself has to agree with the box, or the screen is showing two different splits.
    it "shows the row funded at the figure that was typed" do
      fill_in "Amount for Rent", with: "200"
      click_on "Update figures"

      within("[data-pool-name='Rent']") do
        expect(page).to have_field("Amount for Rent", with: "200.00")
        expect(page).to have_content("$200.00 of $500.00")
      end
    end

    # `Σ pools == your bank balance`. The $300 Rent did not take does not evaporate and does not
    # cascade down to Groceries either — AllocationCommitter applies the override to that row and
    # leaves the rest of the split alone, so the money stays in the buffer. Both halves asserted,
    # because a screen that cascaded would also make the buffer figure move.
    it "leaves what the envelope did not take in the buffer, and does not re-cascade it" do
      within("#distribution-buffer") { expect(page).to have_content("$500.00 → $0.00", normalize_ws: true) }
      within("[data-pool-name='Groceries']") { expect(page).to have_content("$200.00 of $400.00") }

      fill_in "Amount for Rent", with: "200"
      click_on "Update figures"

      within("#distribution-buffer") { expect(page).to have_content("$500.00 → $300.00", normalize_ws: true) }
      within("[data-pool-name='Groceries']") { expect(page).to have_content("$200.00 of $400.00") }
    end

    # "Ran out here" is a statement about the ACCOUNT running dry. An override is the user
    # choosing, so it must not move that line or its figure — the $200 Groceries misses is the
    # cash's doing both before and after Rent is cut to $200.
    it "does not blame the account for a choice the user made" do
      fill_in "Amount for Rent", with: "200"
      click_on "Update figures"

      expect(page).to have_content("ran out here · $200.00 unfunded")
      expect(page).to have_content("$200.00 of what your envelopes asked for isn't there")
    end

    # The other direction of the trade, which a one-sided implementation gets wrong by printing
    # "moving -$300.00 onto your next period".
    it "says the opposite when the user puts in more than the proposal" do
      fill_in "Amount for Rent", with: "800"
      click_on "Update figures"

      within("[data-consequence='Rent']") do
        expect(page).to have_content(
          "You're covering $300.00 early. #{next_period} will need $200.00 instead of $500.00, " \
          "the last period before #{due_on.strftime("%b %-d")}.",
          normalize_ws: true
        )
      end
      # Overfunding past what the account holds is allowed and stated rather than refused: the
      # buffer goes red, which is the true thing about an account that has been over-allocated.
      within("#distribution-buffer") { expect(page).to have_content("$500.00 → -$300.00", normalize_ws: true) }
    end

    # AMENDMENT D / SPEC §5: an override and a rule change must not look alike, and the screen
    # says which one this is in words — before anything has been edited, because the moment it
    # matters is the moment before the first edit.
    it "says on screen that an edit is a one-off and not a rule change" do
      expect(page).to have_content(
        "An edit here is a one-off for this distribution only — it does not change the rule",
        normalize_ws: true
      )
      expect(page).to have_content("To change the rule itself, edit the envelope's budget")
    end

    # THE NEVER-FUNDED RATE ENVELOPE, which is the shape PoolCalculator::Pending#funded_on
    # exists for. Groceries has no movements at all, so #last_funded_on is nil and its rate
    # period reads as open — the projection would then sweep nothing, hold the $100 into the
    # next period and report it asking $300 instead of $400. It is funded by THIS distribution,
    # so next period sweeps it back and tops it up to $400 either way, and there is nothing to
    # say. Paired with Rent's line on the same render.
    it "says nothing about a rate envelope this distribution funds for the first time" do
      fill_in "Amount for Groceries", with: "100"
      fill_in "Amount for Rent", with: "200"
      click_on "Update figures"

      within("[data-pool-name='Groceries']") { expect(page).to have_content("$100.00 of $400.00") }
      expect(page).to have_no_css("[data-consequence='Groceries']")
      expect(page).to have_css("[data-consequence='Rent']")
    end

    # AMENDMENT E: this task adds no writes. The override lives in the query string and in the
    # boxes; the ledger is untouched until Task 6's confirm.
    it "writes nothing" do
      expect { fill_in("Amount for Rent", with: "200") && click_on("Update figures") }
        .not_to(change { [PoolMovement.count, Entry.count] })

      expect(page).to have_css("[data-consequence='Rent']")
    end
  end

  # THE ARITHMETIC THAT TELLS A RECOMPUTATION FROM A SUBTRACTION. Same $2,000 bill, but due far
  # enough out that four periods remain today and three remain next period. $300 held back is
  # $100 a period, not $300 — a screen that added the shortfall onto the current ask would print
  # $700 here.
  #
  # Boundaries fall today, +14, +28, +42; a bill due +45 therefore has four periods today and
  # three from +14. $2,000 less $1,000 held is $1,000 over four periods = $250 a period.
  describe "a dated bill with several periods left", :aggregate_failures do
    before do
      dated_envelope("Rent", 2_000, anchor_date: Date.current + 45, funded: 1_000, priority: 1)
      rate_envelope("Groceries", 400, priority: 2)
      deposit(1_300, on: Date.current - 14)
      deposit(200, on: Date.current)
      visit new_distribution_path
    end

    it "spreads the shortfall over the periods that remain" do
      expect(page).to have_field("Amount for Rent", with: "250.00")

      fill_in "Amount for Rent", with: "50"
      click_on "Update figures"

      within("[data-consequence='Rent']") do
        # $1,000 − $50 = $950 over the three periods left from +14 is $316.67, against $250 had
        # the proposal stood. `$550.00` is what a subtraction would have printed.
        expect(page).to have_content("#{next_period} will need $316.67 instead of $250.00", normalize_ws: true)
        # What a subtraction would have printed: the $200 held back added onto the current ask.
        expect(page).to have_no_content("$450.00")
        # Three periods remain, so this is NOT the last one and the clause must stay off. Paired
        # with the example above, which is the same helper printing it.
        expect(page).to have_no_content("the last period before")
      end
    end
  end

  # THE RED CASE (spec §5, amendment C). A one-time $2,000 bill due in five days, with the next
  # boundary not until +14: today is the only distribution that can reach it. Underfund it and
  # the envelope lands in `won't make it` — an existing state, in the app's existing red.
  describe "an override that leaves an envelope unable to recover", :aggregate_failures do
    let(:due_on) { Date.current + 5 }

    before do
      dated_envelope("Rent", 2_000, anchor_date: due_on, interval_months: nil, funded: 1_000, priority: 1)
      # $500 available against a $1,000 ask, so the proposal itself funds $500 — which is what
      # makes "override it to the full $1,000" a real edit whose consequence has to be gated,
      # rather than a figure that happens to equal the proposal and is not an override at all.
      deposit(1_500, on: Date.current - 14)
      visit new_distribution_path
    end

    # The screen is already open on this fixture and the row already carries the red label,
    # because nothing has been funded yet — so the presence of the consequence line, and only
    # that, is what the override adds.
    it "says nothing about a row nobody has touched" do
      within("[data-pool-name='Rent']") do
        expect(page).to have_content("won't make it · #{due_on.strftime("%b %-d")}")
      end
      expect(page).to have_no_css("[data-consequence]")
    end

    it "uses the won't-make-it red rather than the amber of a trade" do
      fill_in "Amount for Rent", with: "200"
      click_on "Update figures"

      # The amber sentence must NOT be here: this is not a trade, and there is no next period to
      # move anything onto.
      within("[data-consequence='Rent']") do
        expect(page).to have_content(unrecoverable_sentence, normalize_ws: true)
        expect(page).to have_no_content("onto your next period")
      end
      expect(page).to have_css("[data-consequence='Rent'].text-status-danger")
      expect(page).to have_no_css("[data-consequence='Rent'].text-status-warning")
    end

    def unrecoverable_sentence
      "won't make it · #{due_on.strftime("%b %-d")} — the $800.00 still missing has no " \
        "period left to arrive in, so nothing after this distribution can fix it."
    end

    # The other direction: fund it in full and there is no consequence at all, on the same
    # fixture that produced the red one.
    it "says nothing when the override covers the bill" do
      expect(page).to have_field("Amount for Rent", with: "500.00")

      fill_in "Amount for Rent", with: "1000"
      click_on "Update figures"

      within("[data-pool-name='Rent']") { expect(page).to have_field("Amount for Rent", with: "1000.00") }
      expect(page).to have_no_css("[data-consequence]")
    end
  end

  # "Editing a dateless goal shows nothing, because nothing changes" (spec §5). A rate envelope
  # is the same story for a different reason: its leftover is swept back and it is topped up to
  # its full rate again, so what it got this period does not reach the next one.
  #
  # Both are asserted BESIDE a dated bill on the same screen that DOES print a consequence, so
  # the silence is the gate firing rather than the partial being missing.
  describe "edits that change nothing downstream", :aggregate_failures do
    let(:due_on) { Date.current + 20 }

    before do
      dated_envelope("Rent", 2_000, anchor_date: due_on, funded: 1_000, priority: 1)
      # Funded a fortnight ago, so its rate period has closed and its $85 is swept back.
      rate_envelope("Groceries", 400, funded: 85, priority: 2)
      goal("Vacation", target: 2_400, rate: 150, priority: 3)
      deposit(1_500, on: Date.current - 14)
      deposit(200, on: Date.current)
      visit new_distribution_path
    end

    it "says nothing about an envelope that is swept and topped back up" do
      fill_in "Amount for Groceries", with: "100"
      fill_in "Amount for Rent", with: "200"
      click_on "Update figures"

      within("[data-pool-name='Groceries']") { expect(page).to have_field("Amount for Groceries", with: "100.00") }
      expect(page).to have_no_css("[data-consequence='Groceries']")
      # The paired positive: the same render DOES print one, on the row whose ask really moves.
      expect(page).to have_css("[data-consequence='Rent']")
    end

    it "says nothing about a dateless goal" do
      fill_in "Amount for Vacation", with: "50"
      fill_in "Amount for Rent", with: "200"
      click_on "Update figures"

      within("[data-pool-name='Vacation']") { expect(page).to have_field("Amount for Vacation", with: "50.00") }
      expect(page).to have_no_css("[data-consequence='Vacation']")
      expect(page).to have_css("[data-consequence='Rent']")
    end
  end

  # MY READING, NOT THE BRIEF'S, and it is reported as such: the gate is "the per-period ask
  # actually changes", and a dateless goal within one contribution of its target is the one shape
  # where editing it DOES change the ask. $2,300 of a $2,400 goal at $150 a period asks $100 —
  # the remainder, not the rate — so funding $40 leaves $60 for next period where funding $100
  # would have finished it.
  #
  # The alternative reading is that a dateless goal never speaks, whatever the arithmetic says.
  # If that is the ruling, Consequence#worth_saying? is the one place it changes.
  describe "a dateless goal one contribution from its target", :aggregate_failures do
    before do
      goal("Vacation", target: 2_400, rate: 150, funded: 2_300, priority: 1)
      rate_envelope("Groceries", 400, priority: 2)
      deposit(2_400, on: Date.current - 14)
      deposit(200, on: Date.current)
      visit new_distribution_path
    end

    it "does speak, because its ask really moves" do
      within("[data-pool-name='Vacation']") { expect(page).to have_field("Amount for Vacation", with: "100.00") }

      fill_in "Amount for Vacation", with: "40"
      click_on "Update figures"

      within("[data-consequence='Vacation']") do
        expect(page).to have_content("#{next_period} will need $60.00 instead of $0.00", normalize_ws: true)
        # No rule with a date, so there is no date to name and the clause stays off.
        expect(page).to have_no_content("the last period before")
      end
    end
  end

  private

  # A bill: an anchored rule with a due date. `rule` goes straight to the budget factory, so an
  # example that needs a due date which never rolls says `interval_months: nil` in its own words
  # rather than through a flag this helper would have to interpret.
  def dated_envelope(name, amount, funded: nil, priority: 0, **rule)
    pool = create(:pool, :budget_pool, user: user, account: checking, name: name, priority: priority)
    create(:pool_budget, pool: pool, amount: amount, interval_months: 12, **rule)
    create(:pool_movement, from_pool: checking, to_pool: pool, amount: funded, date: Date.current - 14) if funded
    pool
  end

  # A rate envelope: no anchor, so it asks for its amount every period and its leftover sweeps.
  def rate_envelope(name, rate, funded: nil, priority: 0)
    pool = create(:pool, :budget_pool, user: user, account: checking, name: name, priority: priority)
    create(:pool_budget, :per_paycheck_rate, pool: pool, amount: rate)
    create(:pool_movement, from_pool: checking, to_pool: pool, amount: funded, date: Date.current - 14) if funded
    pool
  end

  # A savings pool with a target and a rate rule and no anchor — PoolCalculator#dateless_goal?.
  def goal(name, target:, rate:, funded: nil, priority: 0)
    pool = create(
      :pool,
      :savings_pool,
      user: user,
      account: checking,
      name: name,
      target_amount: target,
      priority: priority
    )
    create(:pool_budget, :per_paycheck_rate, pool: pool, amount: rate)
    create(:pool_movement, from_pool: checking, to_pool: pool, amount: funded, date: Date.current - 14) if funded
    pool
  end

  def deposit(amount, on:)
    category = create(:category, :income, user: user, pool: checking)
    create(:entry, item: create(:item, category: category), amount: amount, date: on)
  end
end
