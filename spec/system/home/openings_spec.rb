# frozen_string_literal: true

require "rails_helper"

# ** "YOUR ACCOUNTS": ONE CARD, ONE QUESTION PER ACCOUNT (account-openings spec §3). ** Henry,
# 2026-09-06: "Not many people are going to know how much TOTAL money they have and then divide it
# all off. Instead they just want to put in what their accounts are currently worth. The fact you
# have to get the ordering exactly right is bad user experience." So the screen this file is about
# asks one thing of each account, in any order, and shows back exactly what was typed.
#
# ── DELETED, WITH THEIR SUCCESSORS HERE (the two onboarding steps this card replaced):
#
#   `spec/system/home/new_account_spec.rb`'s "funding a fresh account" pair — "moves the entered
#   balance from main, then the card is gone" and "shows the card only on a non-main account's
#   section". Successors: "saves what an account holds" and the order-independence example, where
#   MAIN is asked the same question as everyone else rather than exempted from it.
#
#   `spec/system/home/accounts_spec.rb`'s "surfaces a fund-this-account card outside the line" and
#   "surfaces the opening-balance card outside the line" — one per deleted step. Successor: "keeps
#   an account that has not answered out of the line" (kept in that file, since the SPLIT is what
#   that file is about) plus this file's rows and their disappearance.
#
# THE FIGURES ARE PLANTED AND RE-DERIVED IN THE COMMENT THAT USES THEM: every arithmetic assertion
# below states where its number comes from, because a screen that shows a plausible wrong figure is
# exactly the failure this design exists to prevent.
RSpec.describe "Home Openings", type: :system do
  let(:user) { create(:user, period_cadence: :biweekly, period_anchor_date: Date.current) }
  # rubocop:disable RSpec/LetSetup -- nothing NAMES it and every example needs it: the FIRST account a
  # user is given becomes their main one, and this file's whole shape is "Checking is main, and it is
  # asked what it holds exactly like everybody else". Examples reach it by name in the DOM.
  let!(:checking) { create(:pool, :account, user: user, name: "Checking") }
  # rubocop:enable RSpec/LetSetup

  before { sign_in user, scope: :user }

  def card = find("[data-accounts-onboarding]")

  def row(name) = find("[data-account-row='#{name}']")

  def line = find("[data-accounts-line]")

  def account_card(name) = find("[data-account-group='#{name}']")

  # SAVE ONE ROW IN THE CARD. `within` the row's own form, so an example that saved the wrong
  # account's field would fail here rather than quietly assert about the right one.
  def say_it_holds(name, amount)
    within(row(name)) do
      fill_in "What's in it right now", with: amount
      click_button "Save"
    end
    expect(page).to have_content("#{name} holds")
  end

  # THE **EDIT BALANCE** DOOR: open the accounts line, open the card's own disclosure, save the row.
  # It is the same form the card above renders for an account that has not answered yet.
  def correct(name, amount)
    line.click
    within(account_card(name)) do
      find("[data-edit-balance='#{name}'] summary").click
      fill_in "What's in it right now", with: amount
      click_button "Save"
    end
  end

  def add_account(name, balance = nil)
    within("form[action='#{bank_accounts_path}']") do
      fill_in "Account name", with: name
      fill_in "What's in it right now", with: balance if balance
      click_button "Add an account"
    end
    expect(page).to have_content("#{name} added.")
  end

  # ── THE CARD ───────────────────────────────────────────────────────────────────────────────────

  it "asks every account what is in it, main included", :aggregate_failures do
    create(:pool, :account, user: user, name: "Ally")

    visit root_path

    expect(card).to have_content("Your accounts")
    expect(card).to have_css("[data-account-row='Checking']")
    expect(card).to have_css("[data-account-row='Ally']")
    expect(card).to have_button("Add an account")
  end

  # ** THE FIGURE TYPED IS THE FIGURE SHOWN, and main's answer is its own — nothing is divided. **
  # Re-derived: Checking says $300 and holds $300, which is the hero's "In checking".
  it "saves what an account holds", :aggregate_failures do
    visit root_path

    say_it_holds("Checking", "300")

    expect(page).to have_css("[data-in-checking]", text: "$300.00")
    expect(page).to have_no_css("[data-account-row='Checking']")
  end

  # ** ORDER INDEPENDENCE, ON THE SCREEN (the ruling that started the spec). ** Three accounts, the
  # balances saved in an order that puts MAIN IN THE MIDDLE — Ally first, checking second, HYSA last.
  # Re-derived: each save is self-contained, so Checking reads its own $300 and the other two read
  # $500 + $200 = $700 "Elsewhere". Under the old two-step onboarding this order was a trap: funding
  # Ally before correcting main and then correcting main left main short by exactly the funding.
  it "shows the figures typed whatever order they were typed in", :aggregate_failures do
    visit root_path
    add_account("Ally")
    add_account("HYSA")

    say_it_holds("Ally", "500")
    say_it_holds("Checking", "300")
    say_it_holds("HYSA", "200")

    expect(page).to have_css("[data-in-checking]", text: "$300.00")
    expect(page).to have_css("[data-other-accounts-total]", text: "$700.00")
    expect(line).to have_content("$700.00 across 2 other accounts")
  end

  # ONBOARDING IS OVER WHEN THE LAST ACCOUNT ANSWERS (§3) — nothing announces it; the rows simply run
  # out and the add row is all that is left.
  it "is finished when the last account has answered", :aggregate_failures do
    visit root_path
    add_account("Ally", "500")

    expect(card).to have_css("[data-account-row='Checking']")

    say_it_holds("Checking", "300")

    expect(page).to have_no_css("[data-account-row]")
    expect(card).to have_button("Add an account")
  end

  # ADDING AN ACCOUNT AND SAYING WHAT IS IN IT IS ONE ROW, because for the user it is one act.
  # Re-derived: Ally is added holding $500 and never appears as a question — its card is behind the
  # accounts line with the figure on it.
  it "opens an account at the balance it was added with", :aggregate_failures do
    visit root_path

    add_account("Ally", "500")

    expect(page).to have_no_css("[data-account-row='Ally']")
    line.click
    expect(account_card("Ally")).to have_content("balance now $500.00")
  end

  # ── EDIT BALANCE (§2: the correction rewrites the record) ───────────────────────────────────────

  # ** THE CORRECTION EDITS THE ONE RECORD, AND THE COUNT IS THE PIN. ** Re-derived: Ally opened at
  # $500 and is corrected to $650, so Elsewhere goes $700 → $850 ($650 + $200) — and there are still
  # exactly THREE opening entries, one per account, not four. Henry: "Corrections should be done on
  # the same initial entry."
  it "corrects a balance in place rather than adding a second record", :aggregate_failures do
    visit root_path
    add_account("Ally", "500")
    add_account("HYSA", "200")
    say_it_holds("Checking", "300")

    correct("Ally", "650")

    expect(page).to have_content("Ally holds $650.00")
    expect(page).to have_css("[data-other-accounts-total]", text: "$850.00")
    expect(page).to have_css("[data-in-checking]", text: "$300.00")
    expect(Entry.where.not(opening_account_id: nil).count).to eq(3)
  end

  # THE FIELD OPENS ON TODAY'S BALANCE, because that is the figure the user is being asked to confirm
  # or correct — not a blank, which would read as "start again".
  it "opens the edit row on what the account holds today" do
    visit root_path
    add_account("Ally", "500")

    line.click
    find("[data-edit-balance='Ally'] summary").click

    expect(account_card("Ally")).to have_field("What's in it right now", with: "500.00")
  end

  # ── THE NARROW BREAKPOINT ──────────────────────────────────────────────────────────────────────
  #
  # A TRUE 375px LAYOUT VIEWPORT via CDP — `money_spec.rb`'s mechanism, copied deliberately: Chrome
  # refuses a headless window narrower than 500px, so `resize_to(375, …)` is really a 500px test
  # wearing a 375 label. `Emulation.setDeviceMetricsOverride` sets the LAYOUT viewport, which is what
  # CSS media queries read.
  describe "on a narrow screen" do
    before do
      page.driver.browser.execute_cdp(
        "Emulation.setDeviceMetricsOverride", width: 375, height: 667, deviceScaleFactor: 1, mobile: false
      )
    end

    # THE ROW STACKS RATHER THAN SQUEEZING: the account's name, the field and Save cannot share a
    # 375px line, and the field is the thing that must not shrink to nothing. The pin is Selenium's
    # own geometry — no `evaluate_script`, which leaves the session in a state Capybara's teardown
    # does not survive here (CLAUDE.md's first cause wearing a different last statement).
    it "keeps a row's field inside a 375px viewport", :aggregate_failures do
      create(:pool, :account, user: user, name: "Ally Savings Account")

      visit root_path

      field = row("Ally Savings Account").find("input[type='number']").native.rect
      save = row("Ally Savings Account").find("input[type='submit']").native.rect

      expect(field.x + field.width).to be <= 375
      expect(save.y).to be > field.y
    end
  end
end
