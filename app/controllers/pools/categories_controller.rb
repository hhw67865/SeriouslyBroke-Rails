# frozen_string_literal: true

module Pools
  class CategoriesController < ApplicationController
    before_action :set_pool

    # GET /pools/:id/categories
    def index
      # Only load what's actually accessed in Ruby code:
      # - pool for conflict detection ("Connected to other goal")
      # CategoryCalculator uses direct SQL queries, not Ruby associations
      # EXPENSE CATEGORIES ONLY (plan 3, task 5). This was `["savings", "expense"]` — the two types
      # that could reach a pool's balance — and the savings half is gone: money arrives in a pool as
      # a `PoolMovement`. An INCOME category is excluded for the reason it always was: it must name
      # an account (`Category#income_must_land_in_an_account`), so it is not a connection this
      # screen can offer or take away.
      @all_categories = current_user.categories
        .expenses
        .includes(:pool)
        .order(:name)
      @connected_category_ids = @pool.categories.pluck(:id)

      # Group categories to show conflicts
      @categories_with_other_pools = @all_categories.where.not(pool: [nil, @pool])
        .group_by(&:pool)
    end

    # PATCH /pools/:id/categories
    #
    # DISCONNECTING HANDS THE CATEGORY BACK TO AN ACCOUNT, IT DOES NOT NULL IT (plan 3, task 3).
    # This wrote `pool_id: nil`, and `Category belongs_to :pool` refuses that now — `update` returns
    # false, nothing changes, and the user reads "Categories updated successfully!" over a category
    # that is still connected. Found in the browser suite, not reasoned about.
    #
    # The destination is the SAME ONE `Pool#hand_categories_to_the_account` uses when a pool is
    # destroyed: the pool's own account, which is what keeps `Σ pools` conserved — the category's
    # whole history moves into the buffer rather than out of the pool tree.
    #
    # REFUSED UP FRONT WHERE THERE IS NOWHERE TO HAND THEM, rather than attempted and reported as a
    # success. The first fix took `@pool.account || current_user.default_account` and stopped there,
    # which left the exact defect it was fixing standing on two arms one branch over: an ACCOUNT has
    # no `account` of its own by the model's own rule and `users.default_account_id` is nullable
    # with nothing in this app creating one, so the fallback can be nil; and where the fallback IS
    # this very pool, handing a category "back" to the pool it is being disconnected FROM is a
    # no-op. Both would have written nothing under a green flash message. Each gets its own sentence
    # because they are different problems with different fixes.
    #
    # NOTHING IS WRITTEN ON EITHER REFUSAL — not even the connect half. A screen that added
    # categories while silently declining to remove others would leave the checkboxes and the data
    # disagreeing, which is the same class of lie one layer up.
    def update
      category_ids = submitted_category_ids
      leaving = @pool.categories.where.not(id: category_ids).to_a
      refusal = leaving.any? && disconnect_refusal

      return redirect_to categories_pool_path(@pool), alert: refusal if refusal

      apply(leaving, category_ids)
    end

    private

    # THE BLANK SENTINEL IS DROPPED, AND WITHOUT THIS THE DISCONNECT WAS A NO-OP — a defect that
    # predates plan 3 and was found measuring the refusal arms below.
    #
    # The form's checkboxes are `form.check_box :category_ids, { multiple: true }, category.id, ""`,
    # so Rails emits a hidden `""` for every box and an all-unchecked submission arrives as
    # `[""]`. On a uuid column ActiveRecord casts that blank to nil, and a SINGLE-element array
    # renders as `"categories"."id" != NULL` — which is NULL for every row, so `where.not` matched
    # NOTHING and unchecking every category disconnected none of them. Measured, both spellings:
    #
    #   where.not(id: [""])            => id != NULL          => 0 rows  (silently wrong)
    #   where.not(id: ["", other_id])  => NOT (id = ? OR NULL) => the right rows
    #
    # Which is why the screen appeared to work: the only example that exercised it unchecked one box
    # AND checked another, so the array was never a lone blank. Rejecting blanks makes the two
    # spellings agree, and an empty array renders `id != NULL`-free as `1=1`.
    def submitted_category_ids = Array(params[:category_ids]).compact_blank

    # THE RETURN VALUE IS CHECKED, and that is the general form of the same lesson: a validation
    # this controller cannot see (a name collision, a type rule, the next one somebody adds) must
    # not become a success message. The refusals above make the KNOWN failure impossible; this
    # catches the ones nobody has thought of yet.
    def apply(leaving, category_ids)
      failed = leaving.reject { |category| category.update(pool: disconnect_destination) }
      joining = current_user.categories.where(id: category_ids)
      failed += joining.reject { |category| category.update(pool_id: @pool.id) }

      if failed.any?
        redirect_to categories_pool_path(@pool),
                    alert: "Could not update #{failed.map(&:name).to_sentence}."
      else
        redirect_to @pool, notice: "Categories updated successfully!"
      end
    end

    # nil when the disconnect can go ahead; the sentence to print when it cannot.
    def disconnect_refusal
      return nil if disconnect_destination.present? && disconnect_destination != @pool

      if disconnect_destination == @pool
        "#{@pool.name} is where disconnected spending goes, so there is nowhere to move these " \
          "categories to. Point them at another pool from its own page instead."
      else
        "Disconnecting a category needs an account to hand its spending back to, and " \
          "#{@pool.name} has none behind it. Nominate a default account first."
      end
    end

    def disconnect_destination
      return @disconnect_destination if defined?(@disconnect_destination)

      @disconnect_destination = @pool.account || current_user.default_account
    end

    def set_pool
      @pool = current_user.pools.find(params[:id])
    end
  end
end
