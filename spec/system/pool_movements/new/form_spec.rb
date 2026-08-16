# frozen_string_literal: true

require "rails_helper"

# Task 7, the form itself: how it arrives from a link, how it recomputes, and the two things about
# it that no assertion on its figures can see.
RSpec.describe "Pool Movements New Form", type: :system do
  include_context "with a Checking account to reallocate in"

  describe "arriving and recomputing", :aggregate_failures do
    # THE LINK SHAPE TASK 8 WILL USE, arriving with both ends and the amount already chosen: the
    # boxes come back holding them and the move is one click away.
    it "arrives prefilled from a link" do
      visit new_pool_movement_path(to_pool_id: dentist.id, from_pool_id: car.id, amount: 300)

      expect(page).to have_select("Envelope", selected: "Dentist")
      expect(page).to have_field("How much", with: "300.00")
      expect(find_by_id("from-#{car.id}")).to be_checked
    end

    it "recomputes when the destination and amount are typed in" do
      visit new_pool_movement_path
      select "Dentist", from: "Envelope"
      fill_in "How much", with: "300"
      click_on "Update figures"

      within("[data-damage='Car']") { expect(page).to have_content("$1,000.00 → $700.00") }
    end

    # MEASURED IN A BROWSER, NOT REASONED ABOUT, and this is the screen that found it. The page
    # carries three query parameters, and `shared/_date_selector` re-emitted every one of them as a
    # hidden field — with an id — in each of its four forms. `label for=` and `getElementById` both
    # reach the first match in the document, so `document.getElementById("amount")` here returned
    # `<input type="hidden" name="amount" value="300">` rather than the box the user types in.
    # Every other example passed either way, because Capybara filters invisible elements and landed
    # on the right one by luck — which is why this is asserted directly rather than through
    # `fill_in`.
    #
    # The scrubber is fixed generically (its hidden inputs now render `id: nil`, pinned by
    # spec/system/navbar_spec.rb); this screen's own fields keep the distinct ids they were given
    # while the collision stood, because a form field named for its own query parameter is a shape
    # worth keeping out of a page's id space regardless.
    it "does not share a DOM id with the page chrome" do
      visit new_pool_movement_path(to_pool_id: dentist.id, from_pool_id: car.id, amount: 300)

      expect(duplicate_dom_ids).to be_empty
      expect(page).to have_css("input#move-amount[type=number]", count: 1)
      expect(page).to have_field("How much", with: "300.00")
    end

    # HTML'S IMPLICIT SUBMISSION. Enter in a number field activates the FIRST submit button in tree
    # order — so with the move button first, the most natural keystroke there is in a numeric box
    # would move the money on a screen whose entire purpose is stating the cost first. The
    # distribution screen shipped exactly that defect and it wrote a $2,900 split on a keypress.
    # Both halves on one keystroke: nothing was written, and the recompute that should have
    # happened did.
    it "recomputes rather than moving money when Enter is pressed in the amount box" do
      visit new_pool_movement_path(to_pool_id: dentist.id, from_pool_id: car.id)
      fill_in "How much", with: "300"
      find_field("How much").send_keys(:enter)

      expect(page).to have_css("[data-damage='Car']")
      expect(PoolMovement.where(from_pool: car, to_pool: dentist)).not_to exist
      expect(balance_of("Dentist")).to eq(0)
    end
  end
end
