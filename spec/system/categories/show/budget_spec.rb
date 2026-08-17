# frozen_string_literal: true

require "rails_helper"

# THE CATEGORIES PAGE'S BUDGET BLOCK — spec §8.1's three states plus the account-pointed fourth
# the spec does not name, each asserted in both directions.
#
# `Capybara.exact` is unset in this suite and this page is full of chrome that matches substrings
# ("Budget Management", the sidebar's "Budget" link, "Monthly Budget" in the summary card, the
# "Savings Pool" card directly beneath this one), so every assertion is scoped to
# `[data-budget-block]` and every positive is paired with a negative. An unscoped
# `have_content("Budget")` on this page passes in all three states.
RSpec.describe "Categories Show - Budget block", type: :system do
  let(:user) do
    create(:user, period_cadence: :biweekly, period_anchor_date: Date.current, typical_income: 2_400)
  end
  let(:checking) { create(:pool, :account, user: user, name: "Checking") }

  before { sign_in user, scope: :user }

  def block = find("[data-budget-block]")

  def envelope(name)
    create(:pool, :budget_pool, user: user, account: checking, name: name)
  end

  # A category covered by an envelope of the same name, with a rate rule filling it.
  def covered(name, rate: 400)
    envelope(name).tap do |pool|
      create(:pool_budget, :per_period_rate, pool: pool, amount: rate)
      create(:category, :expense, user: user, name: "#{name} Spending", pool: pool)
    end
  end

  # The same, filled by a DATED rule instead of a rate. The clause below only ever prints on
  # `:behind`, and `behind` is a state of an accumulating rule — a rate envelope is `left to spend`
  # however little is in it, so the rate helper above cannot reach the state under test.
  def covered_dated(name, anchor:, amount: 1_200)
    envelope(name).tap do |pool|
      create(:pool_budget, pool: pool, amount: amount, interval_months: 6, anchor_date: anchor)
      create(:category, :expense, user: user, name: "#{name} Spending", pool: pool)
    end
  end

  def fund(pool, amount, on:)
    create(:pool_movement, from_pool: checking, to_pool: pool, amount: amount, date: on)
  end

  def category(name) = user.categories.find_by!(name: name)

  # THE CAVEAT AS A LITERAL, not as a call to the helper that renders it. Asserting
  # `caps_not_counted_sentence` against a page that prints `caps_not_counted_sentence` is a
  # tautology — it would stay green through any rewording, including one that made the two screens
  # disagree with each other. This literal is checked on the Categories page AND on /budget below,
  # so the ONE SPELLING §8.1 asks for is what is actually under test.
  def caps_caveat
    "Your category caps are spending limits, not claims on your income — " \
      "no distribution fills one, so none of them is counted in what your rules need."
  end

  # ------------------------------------------------------------------------------------------
  # State 1 — pool-covered
  # ------------------------------------------------------------------------------------------

  # §8.1: no cap editor (the model forbids a cap here), the envelope named, its balance in the
  # app's one row vocabulary, and a link to /budget. The negative half is the whole point of the
  # state: this category used to render NO block at all, and the wrong fix would have been to
  # render the cap editor for it.
  describe "a category covered by an envelope", :aggregate_failures do
    before do
      covered("Dining Out")
      visit category_path(category("Dining Out Spending"))
    end

    # The name is read off `[data-envelope-name]` rather than asserted against the whole block:
    # "Dining Out" is also the CATEGORY's name ("Dining Out Spending"), which the page header, the
    # breadcrumb and the banner all print, so an unscoped `have_content` here would pass against a
    # block that never named the envelope at all.
    it "names the envelope and how it is doing, and links to the Budget page" do
      expect(block["data-budget-state"]).to eq("pool_covered")
      expect(find("[data-envelope-name]").text).to eq("Dining Out")
      within(block) do
        expect(page).to have_content("$0.00 left")
        expect(page).to have_link("Rules on the Budget page", href: budget_page_path)
        # THE NOUN, from `Pool::NOUNS` since fix 2 and unchanged for a budget pool — this arm is
        # shared with savings pools and used to call both of them an envelope. See the savings
        # half of the pair at the bottom of this describe.
        expect(page).to have_content("Envelope")
        expect(page).to have_no_content("Goal")
      end
    end

    # `Budget#category_must_not_have_pool` refuses a cap on this category, so an editor here would
    # be a control that cannot save. Both the create and the update affordances, because the block
    # renders one or the other in the two states that DO have an editor.
    it "offers no cap editor at all" do
      within(block) do
        expect(page).to have_no_link("Create Budget")
        expect(page).to have_no_link("Update Budget")
        expect(page).to have_no_content("Budget Amount")
      end
    end

    # The caveat belongs beside a cap. Printed here it would explain a rule this category cannot
    # have — and it is the sentence most at risk of being pasted into all three arms.
    it "does not print the cap caveat" do
      within(block) { expect(page).to have_no_content("spending limits, not claims on your income") }
    end

    # A SAVINGS POOL SHARES THIS ARM, and the line between the pooled arms is the model's own:
    # `Budget#pool_must_not_be_an_account` lets a rule sit on a savings pool, so every clause of
    # the envelope sentence is true of one. `$0.00 of $2,000.00` is the row vocabulary's `:saving`
    # state — the same helper, a different state, which is exactly what sharing the arm means.
    it "treats an expense category pointing at a savings goal the same way" do
      goal = create(:pool, :savings_pool, user: user, account: checking, name: "Vet Fund", target_amount: 2_000)
      create(:category, :expense, user: user, name: "Pet Care", pool: goal)

      visit category_path(category("Pet Care"))

      expect(block["data-budget-state"]).to eq("pool_covered")
      expect(find("[data-envelope-name]").text).to eq("Vet Fund")
      within(block) { expect(page).to have_content("$0.00 of $2,000.00") }
    end

    # SAME ARM, DIFFERENT NOUN (2d whole-plan review, fix 2). Sharing the arm is a fact about the
    # model — a rule may sit on either pooled kind — and it is NOT a licence to call both an
    # envelope, which is what this block did while the pool card four inches below called the same
    # pool a "Savings Pool" and the entry form's impact card called it a "goal". The `data-`
    # hooks stay `envelope`-named on both: they name the block's slot, not the pool's kind.
    it "calls a savings pool a goal in the same arm" do
      goal = create(:pool, :savings_pool, user: user, account: checking, name: "Vet Fund", target_amount: 2_000)
      create(:category, :expense, user: user, name: "Pet Care", pool: goal)

      visit category_path(category("Pet Care"))

      within(block) do
        expect(page).to have_content("Goal")
        expect(page).to have_content("comes out of a goal")
        expect(page).to have_no_content("Envelope")
        expect(page).to have_no_content("comes out of an envelope")
      end
    end
  end

  # ------------------------------------------------------------------------------------------
  # The fourth state §8.1 does not name — the category points at an ACCOUNT
  # ------------------------------------------------------------------------------------------

  # `Category#pool_covered?` is `expense? && pool_id.present?`, which says yes to an ACCOUNT, so the
  # first version of this block told such a category it had an envelope, printed the ACCOUNT's name
  # as that envelope and the account's whole balance as this one category's standing, and spoke of
  # "the rule that fills the envelope" — which `Budget#pool_must_not_be_an_account` guarantees can
  # never exist. Every clause was false, and none of it was reachable before this block widened to
  # pool-covered categories.
  #
  # PLANTED THROUGH THE PRODUCTION ROUTE. `Pool#return_holdings_to_the_account` is what puts a
  # category here — destroying an envelope re-points its categories at the account rather than
  # nullifying them, which is what keeps `Σ pools` conserved — so the fixture destroys an envelope
  # instead of assigning an account by hand. A hand-assigned pool would test the render without
  # testing that the shape is reachable.
  describe "a category left pointing at an account", :aggregate_failures do
    before do
      pool = covered("Streaming")
      pool.destroy!
    end

    it "says the spending comes out of the buffer, and names the account" do
      visit category_path(category("Streaming Spending"))

      expect(block["data-budget-state"]).to eq("account_pointed")
      expect(find("[data-account-name]").text).to eq("Checking")
      within(block) do
        expect(page).to have_content("No envelope — this spending isn't budgeted.")
        expect(page).to have_content("It comes out of your buffer.")
      end
    end

    # THE OTHER DIRECTION, AND IT IS THE HALF THAT WAS WRONG: no envelope name, no standing, no
    # "rule that fills the envelope", and still no cap editor — the model forbids a cap for a
    # category pointing at any pool, so the arm that tells the truth must not grow one.
    it "claims no envelope and no standing for it" do
      visit category_path(category("Streaming Spending"))

      expect(block).to have_no_css("[data-envelope-name]")
      expect(block).to have_no_css("[data-envelope-status]")
      within(block) do
        expect(page).to have_no_content("the rule that fills the envelope")
        expect(page).to have_no_link("Create Budget")
        expect(page).to have_no_link("Update Budget")
      end
    end

    # THE SHARPEST HALF. `Category#buffer_funded?` — no pool, or a pool that IS an account — is
    # `SuggestionEngine#rates`' own population, so this is precisely the shape the panel is most
    # likely to be proposing an envelope for, and an envelope is this category's only way out. The
    # first version ran the engine on the uncapped arm only, so the category that needed the
    # pointer most was the one that never got it.
    it "carries the pointer at the Budget page's proposal" do
      bill(category("Streaming Spending"), amount: 180)

      visit category_path(category("Streaming Spending"))

      within(block) do
        expect(page).to have_content("the Budget page is proposing")
        expect(page).to have_link("See it on the Budget page", href: budget_page_path(anchor: "suggestions-dated_bill"))
      end
    end

    # THE LINK AGREES WITH THE SENTENCE ABOVE IT (2d whole-plan review, minors). That sentence
    # already pluralises through `pluralize` — "proposing 2 rules for this category" — while the
    # link under it said "See it", which reads as a pointer at one of the two and leaves the other
    # unaccounted for. Both directions: the singular case is the example directly above, which is
    # what says this did not simply become "them" everywhere.
    it "pluralises the pointer when more than one rule is waiting" do
      2.times { bill(category("Streaming Spending"), amount: 180) }

      visit category_path(category("Streaming Spending"))

      within(block) do
        expect(page).to have_content("proposing 2 rules for this category")
        expect(page).to have_link("See them on the Budget page")
        expect(page).to have_no_link("See it on the Budget page")
      end
    end

    # And with nothing proposed the card is still not a dead end: it makes the offer in the words
    # `entries/_impact`'s honest card already uses for this exact shape.
    it "offers the envelope directly when nothing is proposed" do
      visit category_path(category("Streaming Spending"))

      expect(block).to have_no_css("[data-suggestion-pointer]")
      within(block) { expect(page).to have_link("Give it an envelope on the Budget page", href: budget_page_path) }
    end
  end

  # BOTH SUFFIXES, and each in both directions. This block says how the envelope stands RIGHT NOW,
  # which is the class of caller `HomeHelper#pool_status_label` documents as owing both — a suffix
  # here and not on Home is two screens describing one envelope differently on one afternoon.
  #
  # Two categories rather than two rows on one screen, because this page shows one category: the
  # negative is a second visit. Split from the positive so a block that never prints the suffix at
  # all cannot pass the negative half alone.
  describe "the closed-period suffix", :aggregate_failures do
    before do
      fund(covered("Swept"), 60, on: Date.current - 20.days)
      fund(covered("Live"), 60, on: Date.current)
    end

    it "says which period the money belongs to" do
      visit category_path(category("Swept Spending"))

      within(block) { expect(page).to have_content("$60.00 left · last period") }
    end

    it "stays silent on an envelope funded this period" do
      visit category_path(category("Live Spending"))

      within(block) do
        expect(page).to have_content("$60.00 left")
        expect(page).to have_no_content("last period")
      end
    end
  end

  # SPEC §8'S ROUGH EDGE, on a third screen. `travel_to` rather than `update_column`, because the
  # signal is `budgets.updated_at` against the movement's `created_at` and both have to be written
  # the way the app writes them (see DistributionClock).
  describe "the changed-after-distributing clause", :aggregate_failures do
    include ActiveSupport::Testing::TimeHelpers

    # Captured outside every `travel_to` below: `Date.current` read inside one is the travelled
    # day, and a movement dated on a day the period boundaries do not cover is not this period's
    # distribution at all.
    before do
      on = Date.current
      anchor = on + 3.months
      raised = steady = nil

      travel_to(3.hours.ago) do
        raised = covered_dated("Raised", anchor: anchor)
        steady = covered_dated("Steady", anchor: anchor)
      end

      # Ten dollars against a $1,200 bill three months out leaves both behind, which is the state
      # the clause explains.
      [raised, steady].each { |pool| distribute(pool, 10, on: on) }
      travel_to(1.hour.ago) { raised.budgets.sole.update!(amount: 1_800) }
    end

    def distribute(pool, amount, on:)
      travel_to(2.hours.ago) do
        create(:pool_movement, kind: :allocation, from_pool: checking, to_pool: pool, amount: amount, date: on)
      end
    end

    it "says why this envelope is behind" do
      visit category_path(category("Raised Spending"))

      within(block) do
        expect(page).to have_content("behind")
        expect(page).to have_content("you changed a rule here after distributing")
      end
    end

    it "stays silent on an envelope whose rule nobody touched" do
      visit category_path(category("Steady Spending"))

      within(block) do
        expect(page).to have_content("behind")
        expect(page).to have_no_content("you changed a rule here after distributing")
      end
    end
  end

  # ------------------------------------------------------------------------------------------
  # State 2 — budgetable with a cap
  # ------------------------------------------------------------------------------------------

  # §8.1: the editor STAYS, and the caveat joins it. Nothing here is new except the sentence —
  # which is why the editor is asserted rather than assumed still to be there.
  describe "a category with a cap", :aggregate_failures do
    let!(:cap) { create(:budget, category: create(:category, :expense, user: user, name: "Food"), amount: 500) }

    before { visit category_path(category("Food")) }

    it "keeps the cap editor" do
      expect(block["data-budget-state"]).to eq("capped")
      within(block) do
        expect(page).to have_content("Budget Amount")
        expect(page).to have_content(ActionController::Base.helpers.number_to_currency(500))
        expect(page).to have_link("Update Budget", href: edit_budget_path(cap))
      end
    end

    it "says the cap is not counted in what the rules need" do
      within(block) { expect(page).to have_content(caps_caveat) }
    end

    # ONE SPELLING, ASSERTED ACROSS THE TWO SCREENS THAT OWE IT. This user's only rule is a cap, so
    # `rules_need` is $0.00 and the structural check prints the same sentence under that zero — the
    # exact state §8.1's "one spelling, not two" is about. Same literal, both pages.
    it "prints the same sentence as the Budget page's structural check" do
      visit budget_page_path

      within("[data-caps-note]") { expect(page).to have_content(caps_caveat) }
    end

    it "shows no envelope standing" do
      within(block) do
        expect(page).to have_no_content("Rules on the Budget page")
        expect(page).to have_no_content("Standing")
      end
    end
  end

  # ------------------------------------------------------------------------------------------
  # State 3 — budgetable, no cap
  # ------------------------------------------------------------------------------------------

  # §8.1: unchanged, plus a pointer that renders only where the engine currently proposes. Both
  # directions on the pointer, because a pointer that always renders would send a user to a panel
  # with nothing in it for them, and one that never renders is indistinguishable from the old page.
  describe "a category with neither an envelope nor a cap", :aggregate_failures do
    it "keeps the create-a-cap invitation" do
      target = create(:category, :expense, user: user, name: "Transport")

      visit category_path(target)

      expect(block["data-budget-state"]).to eq("uncapped")
      within(block) do
        expect(page).to have_content("No budget set")
        expect(page).to have_link("Create Budget", href: new_budget_path(category_id: target.id))
        expect(page).to have_no_content(caps_caveat)
      end
    end

    it "points at the Budget page when a rule is being proposed there" do
      bill(create(:category, :expense, user: user, name: "Utilities"), amount: 220)

      visit category_path(category("Utilities"))

      within(block) do
        expect(page).to have_content("the Budget page is proposing")
        expect(page).to have_link("See it on the Budget page", href: budget_page_path(anchor: "suggestions-dated_bill"))
      end
    end

    # A single $50 purchase is neither a bill (one occurrence, under the engine's $100 floor) nor
    # a rate (one period, against a floor of three), so the panel proposes nothing for it — and
    # the block must say nothing rather than point at an empty run.
    it "stays silent when the engine is proposing nothing for it" do
      spender = create(:category, :expense, user: user, name: "Shopping")
      create(:entry, item: create(:item, category: spender), amount: 50, date: Date.current - 3.days)

      visit category_path(spender)

      expect(block).to have_no_css("[data-suggestion-pointer]")
      within(block) { expect(page).to have_no_content("the Budget page is proposing") }
    end
  end

  private

  # A BILL'S SHAPE, straight into `SuggestionEngine`'s dated-bill detector: two payments of the same
  # size a whole month apart, on an item carrying no rule of its own. It takes a CATEGORY rather
  # than a name because both callers need it against a category they already planted — one built by
  # hand, one produced by `Pool#destroy`'s re-point.
  def bill(target, amount:)
    item = create(:item, category: target)
    [2, 1].each { |months| create(:entry, item: item, amount: amount, date: Date.current - months.months) }
  end
end
