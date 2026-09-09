# frozen_string_literal: true

require "rails_helper"

# HOME'S ACCOUNTS, DEMOTED TO ONE LINE (answers-first spec §6). A new file: the accounts used to be
# a stack of cards, one per account, and there was nothing to write a file about.
#
# ** WHAT THE LINE IS AND WHAT THE EXPANSION IS. ** The line answers one question — how much of the
# user's money is somewhere other than checking — because main's balance is already the hero's "In
# Checking" figure and repeating it here would be the screen answering one question twice. The
# expansion is the accounts INDEX: Home carries rename and delete since `pools/index` and
# `pools/show` were deleted, so every account's card has to stay reachable, main's included.
#
# `<details>`/`<summary>` rather than a Stimulus controller — the house idiom
# (`budget_page/_suggestions.html.erb` states the reason): the whole interaction is "show me the
# rest", it needs no JS and it survives a Turbo navigation.
RSpec.describe "Home Accounts", type: :system do
  let(:user) { create(:user, period_cadence: :biweekly, period_anchor_date: Date.current) }
  let!(:checking) { create(:pool, :account, user: user, name: "Checking") }

  before { sign_in user, scope: :user }

  # THE SUMMARY, which carries the copy AND is the thing a user clicks. `[data-accounts]` is the
  # `<details>` around it, for the containment assertions.
  def line = find("[data-accounts-line]")

  def disclosure = find("[data-accounts]")

  def account_card(name) = find("[data-account-group='#{name}']")

  def deposit(amount)
    category = create(:category, :income, user: user, name: "Pay #{SecureRandom.hex(3)}")
    create(:entry, item: create(:item, category: category), amount: amount, date: Date.current)
  end

  # ** MAIN HAS SAID WHAT IT HOLDS (account-openings spec §3). ** `HomePresenter#awaiting_opening?`
  # is open for every freshly created account, so main gets a ROW in the "Your accounts" card and is
  # out of the collapsed set — which is correct, and is exactly what the examples about the COLLAPSED
  # set must not be measuring. It was `opening_balance_recorded!`, which closed the one-time latch by
  # minting the "Opening Balance" category; the signal is `pools.opened_on` now, per account.
  # ** IT GOES THROUGH `AccountOpening` (fix round — MED-4). ** The gate is the opening ENTRY's own
  # existence now — so that deleting the record from the Entries screen puts the question back — and
  # writing `pools.opened_on` by hand would mint an account the app still considers unanswered. The
  # figure is the account's CURRENT balance, so the record written is a zero-amount entry and no
  # movement: nothing about this file's planted money changes.
  def answered!(account = checking)
    opening = AccountOpening.new(user, account, balance: AccountLedger.new(user).balance_of(account))
    raise "could not open #{account.name}: #{opening.errors.full_messages.to_sentence}" unless opening.save
  end

  # A SECOND ACCOUNT WITH MONEY IN IT. Account funding is a move on the PHYSICAL ledger (main → the
  # account it is really in), which is the only way a non-main account comes to hold anything.
  # `:opened` — the account has said what it holds, which is what keeps it out of the "Your accounts"
  # card and inside the line this file is about. The MOVEMENT is what puts money in it: this file is
  # about the line, not about the opening, so the transfer is planted directly rather than through
  # `AccountOpening` (whose own arithmetic is `spec/services/account_opening_spec.rb`'s subject).
  def other_account(name, balance)
    create(:pool, :account, :opened, user: user, name: name).tap do |account|
      create(
        :account_movement,
        from_pool: checking,
        to_pool: account,
        amount: balance,
        date: Date.current,
        kind: :transfer
      )
    end
  end

  # ── THE LINE ───────────────────────────────────────────────────────────────────────────────────

  # THE SPEC'S OWN SENTENCE, with planted figures: $222,000 in one account and $544.87 in another is
  # "$222,544.87 across 2 other accounts". Both halves are asserted, because a line that summed the
  # wrong set would still print a plausible total.
  it "collapses the other accounts to one line with their total", :aggregate_failures do
    deposit(300_000)
    other_account("Ally", 222_000)
    other_account("Vanguard", 544.87)

    visit root_path

    expect(line).to have_content("$222,544.87 across 2 other accounts")
    # Main is NOT in the figure: its balance is the hero's own, and counting it here would be the
    # screen answering "how much is in checking" twice with two different numbers.
    expect(line).to have_no_content("$77,455.13")
  end

  # ** THE NAMES ARE ON THE TILE AND NOT ON THIS LINE (2026-09-06 layout ruling). ** The chips were
  # added here because the line said how MUCH was elsewhere and never WHERE — and the money row's
  # third tile answers that at the top of the screen, beside the figure it is about. Printing the
  # same names again at the foot of the page was the same list twice on one screen. So the line keeps
  # its own job (the total, and the door to the cards behind it), the tile keeps the names, and this
  # is the pin that they did not both keep them.
  it "leaves the account names to the money tile and keeps the total", :aggregate_failures do
    deposit(300_000)
    other_account("Ally", 222_000)
    other_account("Vanguard", 544.87)

    visit root_path

    expect(line).to have_content("$222,544.87 across 2 other accounts")
    expect(page).to have_no_css("[data-line-chip]")
    expect(page).to have_css("[data-other-accounts] [data-account-chip='Ally']")
    expect(page).to have_css("[data-other-accounts] [data-account-chip='Vanguard']")
    # MAIN IS NOT A CHIP, for the reason it is not in the figure: its balance is the money row's own
    # "In checking", and naming it there would answer one question twice.
    expect(page).to have_no_css("[data-account-chip='Checking']")
  end

  # The singular, because "1 other accounts" is the kind of thing a reader stops trusting a screen
  # over.
  it "says one account rather than 1 accounts" do
    deposit(1_000)
    other_account("Ally", 400)

    visit root_path

    expect(line).to have_content("$400.00 across 1 other account")
  end

  # THE OTHER DIRECTION: a user who banks in one place has no "other accounts" to total, and a line
  # reading "$0.00 across 0 other accounts" would be the app inventing an absence.
  it "names the accounts plainly when there is only a main one", :aggregate_failures do
    deposit(1_000)
    answered!

    visit root_path

    expect(line).to have_content("Account details")
    expect(line).to have_no_content("other account")
  end

  # ── THE EXPANSION ──────────────────────────────────────────────────────────────────────────────

  # THE CARDS ARE COLLAPSED, NOT ABSENT — and "collapsed" is asserted through Capybara's own
  # visibility rules, which is what `<details>` gives for free.
  it "hides the account cards until the line is opened", :aggregate_failures do
    deposit(1_000)
    other_account("Ally", 400)

    visit root_path

    expect(page).to have_no_css("[data-account-group='Ally']")
    expect(page).to have_css("[data-account-group='Ally']", visible: :hidden)
  end

  # TODAY'S ACCOUNT CARD, UNCHANGED, INSIDE THE EXPANSION: the balance the bank says, plus the two
  # doors an account still has.
  it "opens to today's account cards", :aggregate_failures do
    deposit(1_000)
    ally = other_account("Ally", 400)

    visit root_path
    line.click

    expect(account_card("Ally")).to have_content("balance now $400.00")
    expect(account_card("Ally")).to have_link("Rename", href: edit_bank_account_path(ally))
    expect(account_card("Ally")).to have_button("Delete")
  end

  # MAIN IS IN THE EXPANSION EVEN THOUGH IT IS NOT IN THE LINE'S FIGURE. The line answers "how much
  # is elsewhere"; the expansion is the accounts index, and main is an account the user may need to
  # rename. Both facts are asserted together, because either alone reads as an accident.
  it "keeps the main account reachable inside the expansion", :aggregate_failures do
    deposit(1_000)
    other_account("Ally", 400)
    answered!

    visit root_path
    line.click

    expect(account_card("Checking")).to have_content("Main account — everything flows through it")
    expect(account_card("Checking")).to have_link("Rename", href: edit_bank_account_path(checking))
    expect(account_card("Checking")).to have_no_button("Delete")
  end

  # AN OVERDRAWN ACCOUNT'S OWN NUMBER, carried from `categories_spec`'s "names an overdrawn
  # account's balance as the debt it is": the card owns the figure, and it is still red inside the
  # expansion.
  it "prints an overdrawn account's balance as the debt it is", :aggregate_failures do
    spend_past_zero(400)
    answered!

    visit root_path
    line.click

    expect(account_card("Checking")).to have_content("balance now -$400.00")
    expect(account_card("Checking")).to have_css(".text-status-danger", text: "-$400.00")
  end

  # SPENDING, NOT A MOVEMENT: money a category has claimed has not left the bank, so an allocation
  # cannot put an account in the red.
  def spend_past_zero(amount)
    groceries = create(
      :category, :expense, user: user, name: "Groceries", funded_since: Date.current - 1.year
    )
    create(:entry, item: create(:item, category: groceries), amount: amount, date: Date.current)
  end

  # ── ONBOARDING STILL SURFACES TOP-LEVEL (spec §6) ──────────────────────────────────────────────

  # THE ADD-ACCOUNT CARD IS ALWAYS TOP-LEVEL: it is the door a user with no accounts needs, and a
  # door behind a chevron is a door a first-time user does not find.
  # OPENED FIRST, deliberately: a collapsed `<details>` hides its fields from Capybara, so this
  # assertion would pass against a card that IS inside the expansion. With it open the containment
  # is the thing being measured.
  it "keeps the add-account door outside the line", :aggregate_failures do
    deposit(1_000)
    other_account("Ally", 400)
    answered!

    visit root_path
    line.click

    expect(page).to have_field("Account name")
    expect(disclosure).to have_no_field("Account name")
  end

  # ** AN ACCOUNT THAT HAS NOT ANSWERED HAS NO CARD AT ALL — it has a ROW (account-openings §3). **
  # It was two examples, one per deleted onboarding step: "surfaces a fund-this-account card outside
  # the line" (step 2, `Real balance today` under a non-main account) and "surfaces the
  # opening-balance card outside the line" (step 3, `Main's real balance today` under main). Both
  # cards are deleted, and what replaced them is not a card in this file's sense: the question lives
  # in the "Your accounts" card, one row per account, which `spec/system/home/openings_spec.rb` owns.
  # What this file still has to say is the SPLIT — an unanswered account is not in the line.
  it "keeps an account that has not answered out of the line", :aggregate_failures do
    deposit(1_000)
    create(:pool, :account, user: user, name: "Ally")

    visit root_path

    expect(page).to have_css("[data-accounts-onboarding] [data-account-row='Ally']")
    expect(page).to have_no_css("[data-accounts] [data-account-group='Ally']", visible: :all)
  end

  # THE OTHER DIRECTION: the moment that account answers, its row is gone and its card drops into
  # the collapsed line with the rest.
  it "drops an account that has answered back into the line", :aggregate_failures do
    deposit(1_000)
    other_account("Ally", 400)

    visit root_path

    expect(page).to have_no_css("[data-account-row='Ally']")
    expect(page).to have_no_css("[data-account-group='Ally']")
    expect(line).to have_content("across 1 other account")
  end

  # ── THE NARROW BREAKPOINT ──────────────────────────────────────────────────────────────────────
  #
  # A TRUE 375px LAYOUT VIEWPORT via CDP — `money_spec.rb`'s mechanism (`hero_spec.rb` until this
  # task renamed it), copied deliberately: Chrome
  # refuses a headless window narrower than 500px, so `resize_to(375, …)` is really a 500px test.
  describe "on a narrow screen" do
    before do
      page.driver.browser.execute_cdp(
        "Emulation.setDeviceMetricsOverride", width: 375, height: 667, deviceScaleFactor: 1, mobile: false
      )
    end

    it "fits the line and its figure inside a 375px viewport", :aggregate_failures do
      deposit(300_000)
      other_account("Ally", 222_000)
      other_account("Vanguard", 544.87)

      visit root_path

      expect(line).to have_content("$222,544.87 across 2 other accounts")

      summary = page.find("[data-accounts-line]").native.rect

      expect(summary.x + summary.width).to be <= 375
    end
  end
end
