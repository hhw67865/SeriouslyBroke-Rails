# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Savings Pools Show - Header Actions", type: :system do
  let(:user) { create(:user) }
  let!(:pool) { create(:pool, user: user, name: "Emergency Fund", target_amount: 10_000) }

  before do
    sign_in user, scope: :user
    visit pool_path(pool)
  end

  describe "page header", :aggregate_failures do
    it "shows savings pool name" do
      expect(page).to have_content("Emergency Fund")
    end

    # Scoped to the breadcrumb nav because the sidebar renders a link labelled exactly
    # "Pools" to the same path and `Capybara.exact` is unset — unscoped, this passed with
    # the breadcrumb deleted outright. The sibling example below is scoped the same way.
    it "shows breadcrumbs" do
      within("nav[aria-label='Breadcrumb']") do
        expect(page).to have_link("Pools", href: pools_path)
      end
      expect(page).to have_content("Emergency Fund")
    end
  end

  describe "edit action", :aggregate_failures do
    it "shows edit button" do
      expect(page).to have_link("Edit", href: edit_pool_path(pool))
    end

    it "navigates to edit page" do
      click_link "Edit"

      expect(page).to have_current_path(edit_pool_path(pool))
      expect(page).to have_content("Edit Pool")
    end
  end

  describe "delete action", :aggregate_failures do
    let(:refusal) do
      "This pool can't be deleted while envelopes and goals still belong to it — " \
        "move them to another account first."
    end

    it "shows delete button with confirmation" do
      delete_button = find("button", text: "Delete")

      expect(delete_button["data-turbo-confirm"]).to be_present
    end

    it "deletes savings pool when confirmed" do
      pool_id = pool.id
      expect(Pool.exists?(pool_id)).to be(true)

      accept_confirm do
        click_button "Delete"
      end

      expect(page).to have_current_path(pools_path)
      expect(page).to have_content("Pool was successfully deleted")
      expect(Pool.exists?(pool_id)).to be(false)
    end

    # THE CONFIRM HAS TO DESCRIBE THE OUTCOME, and since Pool#return_movements_to_the_account
    # the outcome is not "the money is gone". Both directions, because a sentence that is
    # printed over every pool there is says nothing about any of them.
    it "says where an envelope's money goes, naming the account that absorbs it", :aggregate_failures do
      checking = create(:pool, :account, user: user, name: "Checking")
      groceries = create(:pool, :budget_pool, user: user, account: checking, name: "Groceries")
      visit pool_path(groceries)

      confirm = find("button", text: "Delete")["data-turbo-confirm"]

      expect(confirm).to include("returns to Checking's buffer")
      expect(confirm).to include("transfers and spending both re-read as Checking's")
    end

    # THE OTHER DIRECTION, ON AN ACCOUNT (plan 3, task 6). This read "keeps the plain warning on a
    # pool with no account above it" and was planted on the file's own `pool`, an account-less
    # goal — a shape `Pool#account_matches_pool_type` and `CHECK ((pool_type = 0) = (account_id IS
    # NULL))` now refuse. An ACCOUNT is the pool that has nothing above it by its own rule, so it
    # is where the plain warning survives, and the assertion is unchanged.
    it "keeps the plain warning on an account, which has nothing above it to absorb anything" do
      visit pool_path(create(:pool, :account, user: user, name: "Checking"))

      confirm = find("button", text: "Delete")["data-turbo-confirm"]

      expect(confirm).to eq("Are you sure you want to delete this pool? This action cannot be undone.")
    end

    # The §7a chain, deleted through the actual button: $500 into Checking, $100 allocated to B,
    # $60 of it transferred on to C. Deleting B used to take C's inflow with it.
    it "hands the deleted envelope's balance to the buffer and leaves its neighbour alone", :aggregate_failures do
      checking, envelope_b, envelope_c = chain
      visit pool_path(envelope_b)

      accept_confirm { click_button "Delete" }

      expect(page).to have_content("Pool was successfully deleted")
      expect(envelope_c.calculator.balance).to eq(60) # unchanged
      expect(checking.calculator.balance).to eq(440) # 400, plus B's own 40
      expect(Pool.find(checking.id).total).to eq(500) # the deposit, unmoved
    end

    def chain
      checking = create(:pool, :account, user: user, name: "Checking")
      envelope_b = create(:pool, :budget_pool, user: user, account: checking, name: "B")
      envelope_c = create(:pool, :budget_pool, user: user, account: checking, name: "C")
      category = create(:category, :income, user: user, pool: checking, name: "Salary")
      create(:entry, item: create(:item, category: category), amount: 500, date: Date.current)
      create(:pool_movement, from_pool: checking, to_pool: envelope_b, amount: 100, kind: :allocation)
      create(:pool_movement, from_pool: envelope_b, to_pool: envelope_c, amount: 60, kind: :transfer)
      [checking, envelope_b, envelope_c]
    end

    # The real-envelope shape, through the real button: $120 in by movement, $45 out by entries,
    # balance $75. The buffer must rise by 75 and the spending must keep counting — this is the
    # case the movement-only chain above cannot show, and the one the demo turned it up on.
    it "keeps a deleted envelope's spending counting, in the buffer's lane", :aggregate_failures do
      checking, supplies, category = envelope_with_spending
      visit pool_path(supplies)

      accept_confirm { click_button "Delete" }

      expect(page).to have_content("Pool was successfully deleted")
      expect(checking.calculator.balance).to eq(455) # 380 + exactly 75
      expect(category.reload.pool).to eq(checking)
      expect(Pool.find(checking.id).total).to eq(455) # 500 paid in less 45 spent
    end

    def envelope_with_spending
      checking = create(:pool, :account, user: user, name: "Checking")
      supplies = create(:pool, :budget_pool, user: user, account: checking, name: "Supplies")
      salary = create(:category, :income, user: user, pool: checking, name: "Salary")
      create(:entry, item: create(:item, category: salary), amount: 500, date: Date.current)
      create(:pool_movement, from_pool: checking, to_pool: supplies, amount: 120, kind: :allocation)
      spending = create(:category, :expense, user: user, pool: supplies, name: "Supplies Spending")
      create(:entry, item: create(:item, category: spending), amount: 45, date: Date.current)
      [checking, supplies, spending]
    end

    it "refuses to delete an account that still holds pools" do
      checking = create(:pool, :account, user: user, name: "Checking")
      create(:pool, :budget_pool, user: user, account: checking, name: "Groceries")
      visit pool_path(checking)

      accept_confirm do
        click_button "Delete"
      end

      # THE APP'S OWN SENTENCE, NOT RAILS' (plan 3, closing review M4). `restrict_with_error` is
      # still the guard; only its message is written down, in `config/locales/en.yml`, where the
      # reasoning is. "child pools" was the schema's word for a thing this app calls an envelope.
      expect(page).to have_content(refusal)
      expect(Pool.exists?(checking.id)).to be(true)
    end
  end

  describe "breadcrumb navigation", :aggregate_failures do
    it "navigates back to savings pools index" do
      within("nav[aria-label='Breadcrumb']") do
        click_link "Pools"
      end

      expect(page).to have_current_path(pools_path)
      expect(page).to have_content("Accounts and budget envelopes live on Home")
    end
  end
end
