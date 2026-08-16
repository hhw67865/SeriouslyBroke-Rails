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
    # anything is typed: the box is EMPTY, showing what the row gets if it is left alone, and the
    # row says nothing.
    #
    # Empty is not cosmetic. A box pre-filled with the proposal submits that figure back as the
    # row's ask, which pins every untouched row where it was and makes the cascade below
    # impossible — asserted here as the absence of a value, with the placeholder as the paired
    # positive so "no value" cannot pass on a box that failed to render at all.
    it "leaves the box empty, showing what the row gets if it is left alone" do
      within("[data-pool-name='Rent']") do
        expect(page).to have_field("Amount for Rent", with: "", placeholder: "500.00")
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
    # `$200.00` and NOT `$200.00 of $500.00`: the $500 was the rule's ask and the user has
    # overruled it, so this row is now funded in full at the figure they chose. The pairing is
    # what pins that — `Capybara.exact` is unset, so the positive alone passes on either string.
    it "shows the row funded at the figure that was typed" do
      fill_in "Amount for Rent", with: "200"
      click_on "Update figures"

      expect(page).to have_field("Amount for Rent", with: "200.00")
      # Scoped to the row's own figure, not to the whole row: the consequence line beneath it
      # legitimately says "instead of $500.00", and a bare `have_no_content(" of ")` over the row
      # would be an assertion about that sentence instead.
      within("[data-row-amount='Rent']") do
        expect(page).to have_content("$200.00")
        expect(page).to have_no_content(" of ")
      end
    end

    # THE CASCADE, and the reason overrides live inside the fill. Cutting Rent by $300 frees
    # $300; Groceries wanted $200 of it and takes exactly that, and the $100 nobody wanted stays
    # in the buffer.
    #
    # Three figures that DIFFER, so the example cannot pass on a fixture where they coincide:
    # $300 freed, $200 cascaded, $100 into the buffer. The unfunded total falls by the $200
    # Groceries gained — not by the $300 released — which is the arithmetic that tells a real
    # waterfall from a subtraction.
    it "sends what the envelope did not take to the envelope below it" do
      expect_split(groceries: "$200.00 of $400.00", buffer: "$500.00 → $0.00")
      expect(page).to have_content("ran out here · $200.00 unfunded")

      fill_in "Amount for Rent", with: "200"
      click_on "Update figures"

      expect_split(groceries: "$400.00", buffer: "$500.00 → $100.00")
      within("[data-row-amount='Groceries']") { expect(page).to have_no_content(" of ") }
      expect(page).to have_no_content("ran out here")
      expect(page).to have_no_content("isn't there")
    end

    # WHERE THE MONEY WENT, said on the row that moved it. The recipient's own figures are pinned
    # before and after — `$200.00 of $400.00` → `$400.00` — so the example cannot pass on a
    # fixture where they coincide, and the sentence's `$200.00` is checked against a row that
    # visibly gained exactly that.
    #
    # The line belongs to Rent and to nothing else: Groceries changed its number without anybody
    # typing in it, and a clause there would name the wrong actor.
    # THE SENTENCE'S ARITHMETIC, CHECKED AGAINST THE SCREEN rather than against itself.
    # `|moved| == Σ recipients + buffer` holds by construction inside the presenter — two fills
    # spending one `available` — so asserting it there would be `x == x`. Each of the three
    # figures the sentence names is pinned against an independently rendered one: Rent's box
    # (placeholder $500.00 → value $200.00, so $300.00 freed), Groceries' own row ($200.00 of
    # $400.00 → $400.00, so $200.00 gained) and the buffer line ($0.00 → $100.00). $300.00 =
    # $200.00 + $100.00, and all three literals differ, so no two of them can stand in for each
    # other.
    it "says where the freed money went, on the row that freed it" do
      expect_untouched_split

      fill_in "Amount for Rent", with: "200"
      click_on "Update figures"

      expect_redirect("Rent", "That frees $300.00: $200.00 to Groceries and $100.00 to your buffer.")
      expect_edited_split
    end

    def expect_untouched_split
      expect(page).to have_field("Amount for Rent", with: "", placeholder: "500.00")
      within("[data-row-amount='Groceries']") { expect(page).to have_content("$200.00 of $400.00") }
      within("#distribution-buffer") { expect(page).to have_content("$500.00 → $0.00", normalize_ws: true) }
    end

    def expect_edited_split
      expect(page).to have_field("Amount for Rent", with: "200.00")
      within("[data-row-amount='Groceries']") { expect(page).to have_content("$400.00") }
      within("#distribution-buffer") { expect(page).to have_content("$500.00 → $100.00", normalize_ws: true) }
      # The line belongs to the row that moved the money and to nothing else.
      expect(page).to have_no_css("[data-redirect='Groceries']")
    end

    # The case a user would otherwise read as the money vanishing: Groceries is the last row, so
    # cutting it frees money nothing below is waiting for. Said as an answer rather than as a
    # list of one — paired with the example above, where the same edit shape names a recipient.
    it "says so when the freed money reaches nothing and stays in the buffer" do
      fill_in "Amount for Groceries", with: "50"
      click_on "Update figures"

      within("[data-redirect='Groceries']") do
        expect(page).to have_content(
          "That frees $150.00, and nothing below it was waiting — it stays in your buffer.",
          normalize_ws: true
        )
      end
      within("#distribution-buffer") { expect(page).to have_content("$500.00 → $150.00", normalize_ws: true) }
    end

    # The other direction: an override ABOVE the proposal takes its extra out of the envelopes
    # below, and "where did my money go" has the same force asked in reverse. The preposition is
    # the only thing that changes, which is exactly the shape a one-sided implementation gets
    # wrong.
    it "says where the money came from when the edit takes more" do
      within("[data-row-amount='Groceries']") { expect(page).to have_content("$200.00 of $400.00") }

      fill_in "Amount for Rent", with: "800"
      click_on "Update figures"

      within("[data-redirect='Rent']") do
        expect(page).to have_content("That takes $200.00 more: $200.00 from Groceries.", normalize_ws: true)
      end
      within("[data-row-amount='Groceries']") { expect(page).to have_content("$0.00 of $400.00") }
    end

    def expect_split(groceries:, buffer:)
      within("[data-row-amount='Groceries']") { expect(page).to have_content(groceries) }
      within("#distribution-buffer") { expect(page).to have_content(buffer, normalize_ws: true) }
    end

    # The edit made the period all clear, and the table must NOT collapse over it: the boxes are
    # the only way to undo what was just typed, and the density switch would otherwise take them
    # away. Paired against the same fixture before the edit, where the table is open because
    # something is genuinely short.
    it "keeps the table open on a period the edit itself made all clear" do
      expect(page).to have_css("#distribution-waterfall")

      fill_in "Amount for Rent", with: "200"
      click_on "Update figures"

      expect(page).to have_css("#distribution-waterfall")
      expect(page).to have_no_css("#distribution-summary")
      expect(page).to have_field("Amount for Rent", with: "200.00")
    end

    # The other direction of the trade, which a one-sided implementation gets wrong by printing
    # "moving -$200.00 onto your next period".
    #
    # And SPEC §7.3 on the same screen: the account can never be over-allocated. Asking $800 of
    # an account holding $700 takes the $700 and says so — `$700.00 of $800.00` — rather than
    # writing $800 and leaving the buffer at -$100. The clamp is why "covering $200.00 early"
    # rather than $300: the extra the envelope actually received is what moved.
    it "says the opposite when the user puts in more than the proposal" do
      fill_in "Amount for Rent", with: "800"
      click_on "Update figures"

      within("[data-consequence='Rent']") { expect(page).to have_content(covering_early, normalize_ws: true) }
      within("[data-row-amount='Rent']") { expect(page).to have_content("$700.00 of $800.00") }
      within("#distribution-buffer") { expect(page).to have_content("$500.00 → $0.00", normalize_ws: true) }
      # Everything below it is starved instead, which is the honest cost and is stated.
      within("[data-row-amount='Groceries']") { expect(page).to have_content("$0.00 of $400.00") }
    end

    def covering_early
      "You're covering $200.00 early. #{next_period} will need $300.00 instead of $500.00, " \
        "the last period before #{due_on.strftime("%b %-d")}."
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

      within("[data-pool-name='Groceries']") do
        expect(page).to have_field("Amount for Groceries", with: "100.00")
      end
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
      expect(page).to have_field("Amount for Rent", with: "", placeholder: "250.00")

      fill_in "Amount for Rent", with: "50"
      click_on "Update figures"

      within("[data-consequence='Rent']") do
        # $1,000 − $50 = $950 over the three periods left from +14 is $316.67, against $250 had
        # the proposal stood.
        expect(page).to have_content("#{next_period} will need $316.67 instead of $250.00", normalize_ws: true)
        # What a subtraction would have printed: the $200 held back added onto the $250 ask.
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
      # Groceries sits ABOVE Rent, so the account's $1,200 leaves Rent $800 of the $1,000 it
      # needs — which is what makes both "cut Rent further" and "cut Groceries to rescue Rent"
      # real edits rather than figures that happen to equal the proposal.
      rate_envelope("Groceries", 400, priority: 1)
      dated_envelope("Rent", 2_000, anchor_date: due_on, interval_months: nil, funded: 1_000, priority: 2)
      deposit(2_200, on: Date.current - 14)
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

    # The other direction, on the same fixture that produced the red one: cover the bill and
    # nothing is said. It takes two edits, because $1,000 only reaches Rent once Groceries is cut
    # — which is the whole reason the plan wanted the cascade, seen at the point it matters most.
    it "says nothing when the edits cover the bill" do
      within("[data-row-amount='Rent']") { expect(page).to have_content("$800.00 of $1,000.00") }

      fill_in "Amount for Groceries", with: "200"
      fill_in "Amount for Rent", with: "1000"
      click_on "Update figures"

      expect_rent_funded_in_full
      expect(page).to have_no_css("[data-consequence]")
    end

    # THE CASCADE RESCUING AN ENVELOPE, with ONE edit and none of it on the row that is rescued.
    # Cutting Groceries to nothing hands Rent the whole $1,200 and the bill is made — and the
    # rescued row says nothing, because nobody typed in it.
    it "rescues the bill below by cutting the envelope above it" do
      within("[data-row-amount='Rent']") { expect(page).to have_content("$800.00 of $1,000.00") }
      expect(page).to have_content("ran out here · $200.00 unfunded")

      fill_in "Amount for Groceries", with: "0"
      click_on "Update figures"

      expect_rent_funded_in_full
      # The zeroed row keeps its place and its box — there has to be somewhere to type the money
      # back in — and the account's own shortfall is gone.
      expect(page).to have_field("Amount for Groceries", with: "0.00")
      expect(page).to have_no_content("ran out here")
      expect(page).to have_no_css("[data-consequence]")
    end

    # THE CASE THAT MOTIVATES THE SENTENCE. The rescue above happens to a row the user never
    # touched, and its own label still reads `won't make it` because that is where the envelope
    # stands TODAY — so the only thing on the screen that can say the bill is now made is the
    # line on the row that made it, and it has to name Rent by name.
    it "names the row its freed money rescued" do
      within("[data-row-amount='Rent']") { expect(page).to have_content("$800.00 of $1,000.00") }

      fill_in "Amount for Groceries", with: "0"
      click_on "Update figures"

      expect_redirect("Groceries", "That frees $400.00: $200.00 to Rent and $200.00 to your buffer.")
      expect_rent_funded_in_full
      expect(page).to have_no_css("[data-redirect='Rent']")
    end

    # `$1,000.00` and not `$1,000.00 of $1,000.00`: the pairing is what pins that the bill is
    # made rather than that a figure happens to appear on the row.
    def expect_rent_funded_in_full
      within("[data-row-amount='Rent']") do
        expect(page).to have_content("$1,000.00")
        expect(page).to have_no_content(" of ")
      end
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

    # ATTRIBUTION. Two edits at once, and each row's sentence is measured against the split with
    # ITS OWN edit undone and the other left in place — not against the untouched proposal, which
    # would credit each of them with the other's money.
    #
    # The two answers are not merely different sizes, they point in opposite DIRECTIONS: against
    # the untouched proposal Vacation went from $0.00 to $50.00 and would read "that takes $50.00
    # more", when what it actually did was give up the $100.00 Rent's edit had just sent it.
    it "attributes each edit to itself when two rows are edited at once" do
      fill_in "Amount for Rent", with: "200"
      fill_in "Amount for Vacation", with: "50"
      click_on "Update figures"

      expect_redirect("Rent", "That frees $300.00: $200.00 to Groceries, $50.00 to Vacation, and the rest to your buffer.")
      expect_redirect("Vacation", "That frees $50.00, and nothing below it was waiting — it stays in your buffer.")
      # Against the untouched proposal this row would have read "takes $50.00 more" — the wrong
      # direction, not merely the wrong size.
      within("[data-redirect='Vacation']") { expect(page).to have_no_content("takes") }
    end

    # NEITHER ROW PUTS A FIGURE ON THE BUFFER once a second row is edited. Each row's share is
    # true under its own counterfactual and the two overlap — Rent's is $50.00 and Vacation's is
    # $50.00 against a buffer that moved $50.00 in total — so two visible figures would sum past
    # what the screen moved. Paired with the single-edit example above, where the figure IS
    # printed, so the suppression is a rule firing rather than a clause that never renders.
    it "does not let two edited rows each put a figure on the buffer" do
      fill_in "Amount for Rent", with: "200"
      fill_in "Amount for Vacation", with: "50"
      click_on "Update figures"

      # $415 → $50 is the one true buffer figure, and it is on the buffer line where it belongs.
      within("#distribution-buffer") { expect(page).to have_content("$415.00 → $50.00", normalize_ws: true) }
      within("[data-redirect='Rent']") { expect(page).to have_content("the rest to your buffer") }
      within("[data-redirect='Vacation']") { expect(page).to have_content("it stays in your buffer") }
      # The string a per-edit figure would have produced on BOTH rows, summing to $100 against a
      # $50 move.
      expect(page).to have_no_content("$50.00 to your buffer")
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

  # THE CRITICAL THE REVIEW FOUND BY PROBING, and the shape neither of the two-edit examples
  # above could reach: their second edit lands on a dateless goal, whose consequence is suppressed
  # anyway, so the fixture hid the defect. Both edited rows here are DATED bills, so both speak
  # twice — and the two sentences on the second row have to agree with each other.
  #
  # Rent asks $500 and Dentist $300 out of $700, so Dentist starts at $200 of $300. Cutting Rent
  # to $200 funds Dentist in FULL, and Dentist's true counterfactual is therefore $300 — cutting
  # it to $250 WITHHOLDS $50. Measured against the untouched proposal instead it looked like a
  # $50 gain, and the row read "That frees $50.00…" directly above "You're covering $50.00
  # early…": two sentences on one row pointing opposite ways.
  describe "two dated bills edited at once", :aggregate_failures do
    let(:due_on) { Date.current + 20 }

    before do
      dated_envelope("Rent", 2_000, anchor_date: due_on, funded: 1_000, priority: 1)
      dated_envelope("Dentist", 1_200, anchor_date: due_on, funded: 600, priority: 2)
      deposit(2_100, on: Date.current - 14)
      deposit(200, on: Date.current)
      visit new_distribution_path
    end

    it "makes both of the second row's sentences agree in direction" do
      within("[data-row-amount='Dentist']") { expect(page).to have_content("$200.00 of $300.00") }

      fill_in "Amount for Rent", with: "200"
      fill_in "Amount for Dentist", with: "250"
      click_on "Update figures"

      within("[data-redirect='Dentist']") { expect(page).to have_content("That frees $50.00") }
      within("[data-consequence='Dentist']") do
        expect(page).to have_content("You're moving $50.00 onto your next period", normalize_ws: true)
        # The untouched-proposal reading, in both of its halves: the opposite direction, and a
        # baseline ask from a world in which neither edit exists.
        expect(page).to have_no_content("covering")
        expect(page).to have_no_content("$400.00")
      end
    end

    # The same root cause LOSING a sentence rather than reversing one: $200 is exactly what the
    # untouched proposal gave Dentist, so measured against that the edit looks like no edit at
    # all and the `funded == baseline` early return fires — the row then says what it frees and
    # nothing about what it costs later, which amendment B forbids. Its true counterfactual is
    # $300, so it is withholding $100.
    it "still states the consequence when the edit matches the untouched figure" do
      fill_in "Amount for Rent", with: "200"
      fill_in "Amount for Dentist", with: "200"
      click_on "Update figures"

      within("[data-redirect='Dentist']") { expect(page).to have_content("That frees $100.00") }
      within("[data-consequence='Dentist']") do
        expect(page).to have_content("You're moving $100.00 onto your next period", normalize_ws: true)
      end
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
      within("[data-pool-name='Vacation']") do
        expect(page).to have_field("Amount for Vacation", with: "", placeholder: "100.00")
      end

      fill_in "Amount for Vacation", with: "40"
      click_on "Update figures"

      within("[data-consequence='Vacation']") do
        expect(page).to have_content("#{next_period} will need $60.00 instead of $0.00", normalize_ws: true)
        # No rule with a date, so there is no date to name and the clause stays off.
        expect(page).to have_no_content("the last period before")
      end
    end
  end

  # SPEC §5 says every line is editable, and the all-clear density renders no lines — which is not
  # a contradiction (that density is a headline, one summary line and a button) but does leave
  # someone who simply wants to put more into savings on a comfortable period with nothing to type
  # in. One more term in the density switch, and nothing is remembered: a fresh visit collapses
  # again, so the density is still the data's decision everywhere the user has not overruled it.
  describe "a comfortable period", :aggregate_failures do
    before do
      rate_envelope("Groceries", 400, priority: 1)
      goal("Vacation", target: 2_400, rate: 150, priority: 2)
      deposit(2_400, on: Date.current)
      visit new_distribution_path
    end

    # The default half. The absence of boxes is paired with the summary line, so it cannot pass on
    # a screen that failed to render at all.
    it "collapses, with no boxes and a way in" do
      expect(page).to have_css("#distribution-summary")
      expect(page).to have_no_css("#distribution-waterfall")
      expect(page).to have_no_field("Amount for Groceries")
      expect(page).to have_link("Show every envelope")
    end

    it "opens the full table with its boxes when asked" do
      click_on "Show every envelope"

      expect(page).to have_css("#distribution-waterfall")
      expect(page).to have_no_css("#distribution-summary")
      expect(page).to have_field("Amount for Vacation", with: "", placeholder: "150.00")
    end

    # The request has to survive the form, or clearing the last edit collapses the table out from
    # under the boxes mid-edit. Asserted through a full edit cycle rather than on the link alone.
    it "stays open through an edit and through clearing it again" do
      click_on "Show every envelope"
      fill_in "Amount for Vacation", with: "40"
      click_on "Update figures"

      expect(page).to have_field("Amount for Vacation", with: "40.00")

      fill_in "Amount for Vacation", with: ""
      click_on "Update figures"

      expect(page).to have_css("#distribution-waterfall")
      expect(page).to have_field("Amount for Vacation", with: "", placeholder: "150.00")
    end
  end

  private

  def expect_redirect(pool, sentence)
    within("[data-redirect='#{pool}']") { expect(page).to have_content(sentence, normalize_ws: true) }
  end

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
