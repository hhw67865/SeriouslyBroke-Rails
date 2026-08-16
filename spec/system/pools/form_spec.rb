# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Pools Form", type: :system do
  let!(:user) { create(:user) }

  before { sign_in user, scope: :user }

  describe "New Form" do
    before { visit new_pool_path }

    describe "form display", :aggregate_failures do
      it "shows all form elements" do
        expect(page).to have_field("Pool Name")
        expect(page).to have_field("Target Amount")
        expect(page).to have_button("Create Pool")
      end

      it "shows navigation elements" do
        expect(page).to have_link("Cancel")
      end

      it "shows informational content" do
        expect(page).to have_content("How it works")
        expect(page).to have_content("Money arrives in an account")
      end

      it "does not show progress indicator for new pool" do
        expect(page).not_to have_content("Current Progress")
      end
    end

    describe "form validation", :aggregate_failures do
      it "shows error for missing name" do
        fill_in "Target Amount", with: "1000"
        click_button "Create Pool"

        expect(page).to have_content("can't be blank")
        expect(page).to have_field("Pool Name")
      end

      it "shows error for missing target amount" do
        fill_in "Pool Name", with: "Emergency Fund"
        click_button "Create Pool"

        expect(page).to have_content("can't be blank")
        expect(page).to have_field("Target Amount")
      end

      it "shows errors for both missing fields" do
        click_button "Create Pool"

        expect(page).to have_content("can't be blank", count: 2)
      end
    end

    describe "successful submission", :aggregate_failures do
      it "creates savings pool and redirects to show page" do
        fill_in "Pool Name", with: "Emergency Fund"
        fill_in "Target Amount", with: "5000"
        click_button "Create Pool"

        expect(page).to have_content("Pool was successfully created")
        expect(page).to have_current_path(pool_path(Pool.last))
        expect(page).to have_content("Emergency Fund")
      end

      it "creates savings pool with correct attributes" do
        fill_in "Pool Name", with: "Vacation Fund"
        fill_in "Target Amount", with: "2500"
        click_button "Create Pool"

        expect(page).to have_content("Pool was successfully created")
        pool = Pool.last
        expect(pool.name).to eq("Vacation Fund")
        expect(pool.target_amount).to eq(2500)
        expect(pool.user).to eq(user)
      end
    end

    describe "navigation", :aggregate_failures do
      it "returns to index when clicking cancel" do
        click_link "Cancel"
        expect(page).to have_current_path(pools_path)
      end
    end

    # The three fields the form was missing. `pool_params` has permitted all three since
    # Plan 2a, `pools.pool_type` defaults to 2 (savings) and `account_id` is nullable — so
    # without them EVERY pool anybody could create through this app was an account-less
    # savings goal, while Home told those same users in three places to give their pools an
    # account. There was no field anywhere to do it with.
    describe "the kind, the account and the funding order" do
      let!(:checking) { create(:pool, :account, user: user, name: "Checking") }

      before { visit new_pool_path }

      it "offers all three kinds of pool", :aggregate_failures do
        expect(page).to have_select(
          "What kind of pool is this?",
          options: ["Bank account", "Budget envelope", "Savings goal"]
        )
        expect(page).to have_field("Funding Priority")
      end

      # The whole point of the fix, end to end: an envelope, inside an account, ranked.
      it "creates a budget envelope inside an account", :aggregate_failures do
        fill_in "Pool Name", with: "Groceries"
        select "Budget envelope", from: "What kind of pool is this?"
        select "Checking", from: "Account it sits inside"
        fill_in "Funding Priority", with: "3"
        click_button "Create Pool"

        expect(page).to have_content("Pool was successfully created")
        expect(Pool.last).to have_attributes(
          name: "Groceries", pool_type: "budget", account: checking, priority: 3
        )
      end

      # No target on an envelope, so the savings-goal chrome the detail page is built out of
      # has to stay away rather than render 0% toward $0.00 at a pool that never had a goal.
      it "does not report an envelope's progress toward a target it has none of", :aggregate_failures do
        fill_in "Pool Name", with: "Groceries"
        select "Budget envelope", from: "What kind of pool is this?"
        select "Checking", from: "Account it sits inside"
        click_button "Create Pool"

        expect(page).to have_content("Budget envelope in Checking")
        # Case-insensitive because these labels are rendered through `uppercase`, and
        # `have_no_content("Target Goal")` would therefore pass against a page that renders
        # TARGET GOAL in full — green forever, for a reason that has nothing to do with the
        # behaviour. The balance is asserted the same way so both read alike.
        expect(page).to have_content(/current balance/i)
        expect(page).to have_no_content(/target goal/i)
        expect(page).to have_no_content("% complete")
      end

      it "creates a bank account, which sits inside nothing", :aggregate_failures do
        fill_in "Pool Name", with: "Ally Savings"
        select "Bank account", from: "What kind of pool is this?"
        click_button "Create Pool"

        expect(page).to have_content("Pool was successfully created")
        pool = Pool.last
        expect(pool.pool_type).to eq("account")
        expect(pool.account).to be_nil
      end

      # A pool is not a candidate parent for itself, and offering it would let a user build
      # an account that sits inside itself. The second account is here so the select still
      # renders — otherwise this passes on a form that offers no accounts at all.
      it "does not offer the pool being edited as its own account" do
        create(:pool, :account, user: user, name: "Ally")

        visit edit_pool_path(checking)

        expect(page).to have_select(
          "Account it sits inside",
          options: ["No account — nothing can fund this pool", "Ally"]
        )
      end

      # An envelope must name an account, and the model says so. Pinned because the select
      # includes a blank option: the form must not quietly create something unfundable.
      it "refuses an envelope with no account", :aggregate_failures do
        fill_in "Pool Name", with: "Groceries"
        select "Budget envelope", from: "What kind of pool is this?"
        click_button "Create Pool"

        expect(page).to have_content("must be set for budget pools")
        expect(Pool.where(name: "Groceries")).to be_empty
      end
    end

    # A select with nothing in it is the same dead end Home was sending people to — it looks
    # like a field they forgot rather than a step they have not taken.
    describe "before the user has any account" do
      it "says so instead of rendering an empty account select", :aggregate_failures do
        visit new_pool_path

        expect(page).to have_no_select("Account it sits inside")
        expect(page).to have_content("You have no bank accounts yet")
        expect(page).to have_content("make this one a Bank account")
      end
    end

    describe "auto-create categories" do
      it "renders both checkboxes unchecked by default", :aggregate_failures do
        expect(page).to have_field("Create an expense category", type: "checkbox", checked: false)
        expect(page).to have_field("Create a savings category", type: "checkbox", checked: false)
      end

      it "creates only the pool when neither box is checked" do
        fill_in "Pool Name", with: "Plain Pool"
        fill_in "Target Amount", with: "1000"
        click_button "Create Pool"

        expect(Pool.last.categories.count).to eq(0)
      end

      it "creates a linked expense category when the expense box is checked", :aggregate_failures do
        fill_in "Pool Name", with: "Expense Pool"
        fill_in "Target Amount", with: "1000"
        check "Create an expense category"
        click_button "Create Pool"

        pool = Pool.last
        expect(pool.categories.count).to eq(1)
        category = pool.categories.first
        expect(category.name).to eq("Expense Pool Expense")
        expect(category.category_type).to eq("expense")
      end

      it "creates a linked savings category when the savings box is checked", :aggregate_failures do
        fill_in "Pool Name", with: "Savings Pool"
        fill_in "Target Amount", with: "1000"
        check "Create a savings category"
        click_button "Create Pool"

        pool = Pool.last
        expect(pool.categories.count).to eq(1)
        category = pool.categories.first
        expect(category.name).to eq("Savings Pool Savings")
        expect(category.category_type).to eq("savings")
      end

      it "creates both linked categories when both boxes are checked", :aggregate_failures do
        fill_in "Pool Name", with: "Dual Pool"
        fill_in "Target Amount", with: "1000"
        check "Create an expense category"
        check "Create a savings category"
        click_button "Create Pool"

        pool = Pool.last
        expect(pool.categories.pluck(:name)).to contain_exactly(
          "Dual Pool Expense",
          "Dual Pool Savings"
        )
      end
    end
  end

  describe "Edit Form" do
    let!(:pool) { create(:pool, name: "Original Name", target_amount: 1000, user: user) }

    before { visit edit_pool_path(pool) }

    describe "form display", :aggregate_failures do
      it "shows all form elements pre-filled" do
        expect(page).to have_field("Pool Name", with: "Original Name")
        expect(page).to have_field("Target Amount", with: "1000.0")
        expect(page).to have_button("Update Pool")
      end

      it "shows navigation elements" do
        expect(page).to have_link("Cancel")
      end

      it "shows current progress section" do
        expect(page).to have_content("Current Progress")
        expect(page).to have_content("Progress toward goal")
      end
    end

    describe "progress indicator with data", :aggregate_failures do
      let!(:savings_category) { create(:category, category_type: "savings", user: user, pool: pool) }
      let!(:savings_item) { create(:item, category: savings_category) }

      before do
        create(:entry, item: savings_item, amount: 300)
        visit edit_pool_path(pool)
      end

      it "shows current balance and progress" do
        expect(page).to have_content("$300.00")
        expect(page).to have_content("30%")
      end

      it "shows remaining amount" do
        expect(page).to have_content("$700.00")
      end
    end

    describe "form validation", :aggregate_failures do
      it "shows error when name is removed" do
        fill_in "Pool Name", with: ""
        click_button "Update Pool"

        expect(page).to have_content("can't be blank")
        expect(page).to have_field("Pool Name")
      end
    end

    describe "successful update", :aggregate_failures do
      it "updates name and redirects to show page" do
        fill_in "Pool Name", with: "Updated Name"
        click_button "Update Pool"

        expect(page).to have_content("Pool was successfully updated")
        expect(page).to have_current_path(pool_path(pool))
        expect(page).to have_content("Updated Name")
      end

      it "updates target amount" do
        fill_in "Target Amount", with: "5000"
        click_button "Update Pool"

        expect(page).to have_content("Pool was successfully updated")
        pool.reload
        expect(pool.target_amount).to eq(5000)
      end

      it "updates both fields simultaneously" do
        fill_in "Pool Name", with: "New Vacation Fund"
        fill_in "Target Amount", with: "3500"
        click_button "Update Pool"

        expect(page).to have_content("Pool was successfully updated")
        pool.reload
        expect(pool.name).to eq("New Vacation Fund")
        expect(pool.target_amount).to eq(3500)
      end
    end

    # The journey Home sends people on. `_orphans`, `_pool_row` and `_standing` all tell a
    # user with an account-less pool to give it an account — three places, and until this
    # form grew the field there was nowhere in the app to do it. This is that instruction
    # being carried out.
    describe "giving an account-less pool an account" do
      let!(:checking) { create(:pool, :account, user: user, name: "Checking") }

      it "assigns it, so a distribution can finally reach the pool", :aggregate_failures do
        visit edit_pool_path(pool)
        select "Checking", from: "Account it sits inside"
        click_button "Update Pool"

        expect(page).to have_content("Pool was successfully updated")
        expect(pool.reload.account).to eq(checking)
      end

      # And back again, because savings pools may legitimately have none until Plan 3's
      # backfill — the blank option has to actually clear the field, not be inert.
      it "takes the account away again when the blank option is chosen", :aggregate_failures do
        pool.update!(account: checking)

        visit edit_pool_path(pool)
        select "No account — nothing can fund this pool", from: "Account it sits inside"
        click_button "Update Pool"

        expect(page).to have_content("Pool was successfully updated")
        expect(pool.reload.account).to be_nil
      end
    end

    # Both defects the three new fields introduced, driven the way a user meets them.
    describe "the funding priority box" do
      # `pools.priority` is NOT NULL, "" casts to nil, and browser validations are off — so
      # before the model caught it, clearing this box handed the user a 500 instead of a form.
      it "shows an error instead of crashing when the box is cleared", :aggregate_failures do
        fill_in "Funding Priority", with: ""
        click_button "Update Pool"

        expect(page).to have_content("can't be blank")
        expect(page).to have_field("Funding Priority")
        expect(pool.reload.priority).to eq(0)
      end

      it "refuses a negative funding priority", :aggregate_failures do
        fill_in "Funding Priority", with: "-1"
        click_button "Update Pool"

        expect(page).to have_content("must be greater than or equal to 0")
        expect(pool.reload.priority).to eq(0)
      end

      it "accepts a valid funding priority", :aggregate_failures do
        fill_in "Funding Priority", with: "4"
        click_button "Update Pool"

        expect(page).to have_content("Pool was successfully updated")
        expect(pool.reload.priority).to eq(4)
      end
    end

    describe "changing what an account is while envelopes sit inside it" do
      let!(:checking) { create(:pool, :account, user: user, name: "Checking") }
      let!(:ally) { create(:pool, :account, user: user, name: "Ally") }

      # Demoting Checking used to save silently, after which Rent rendered nowhere on Home —
      # not under an account, not among the orphans — while still counting toward the money
      # the period had to cover.
      it "refuses the demotion and says why", :aggregate_failures do
        create(:pool, :budget_pool, user: user, account: checking, name: "Rent")

        visit edit_pool_path(checking)
        select "Budget envelope", from: "What kind of pool is this?"
        select "Ally", from: "Account it sits inside"
        click_button "Update Pool"

        expect(page).to have_content("move them out first")
        expect(checking.reload).to be_pool_type_account
      end

      it "allows the demotion once nothing sits inside it", :aggregate_failures do
        visit edit_pool_path(checking)
        select "Budget envelope", from: "What kind of pool is this?"
        select "Ally", from: "Account it sits inside"
        click_button "Update Pool"

        expect(page).to have_content("Pool was successfully updated")
        expect(checking.reload).to be_pool_type_budget
        expect(checking.account).to eq(ally)
      end
    end

    # `assignable_accounts_for` rejects the pool itself, so a user editing their only account
    # saw an empty collection and, with the branch keyed off that, a panel telling them they
    # had no bank accounts and should make this one — a bank account — a bank account.
    describe "the account panel on a user's only bank account" do
      it "does not claim the user has no bank accounts", :aggregate_failures do
        checking = create(:pool, :account, user: user, name: "Checking")

        visit edit_pool_path(checking)

        expect(page).to have_no_content("You have no bank accounts yet")
        expect(page).to have_no_select("Account it sits inside")
      end
    end

    describe "navigation", :aggregate_failures do
      it "returns to index when clicking cancel" do
        click_link "Cancel"
        expect(page).to have_current_path(pools_path)
      end
    end

    describe "auto-create categories section" do
      it "does not render the checkboxes on the edit form", :aggregate_failures do
        expect(page).not_to have_field("Create an expense category")
        expect(page).not_to have_field("Create a savings category")
      end
    end
  end
end
