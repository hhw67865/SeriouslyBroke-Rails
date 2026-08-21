# frozen_string_literal: true

# HIDING A SUGGESTION, AND SHOWING IT AGAIN (Henry's ruling of 2026-08-20). Two verbs on one
# resource, because that is exactly what the pair is: `create` writes the row that hides a
# suggestion and `destroy` deletes it. There is no `index` — the hidden list renders at the foot of
# the panel the rows came from, which is the only place a user is ever asking the question.
#
# BOTH ACTIONS REDIRECT TO /budget, always. The panel is the whole context for this decision: a
# 204 would leave the user on a page whose row is still on screen, and a page of this resource's
# own would be a screen about a table nobody wants to look at.
#
# OWNERSHIP IS ANSWERED HERE, RECORDS AND NOT IDS, exactly where `BudgetsController` answers it for
# `pool_id` and `item_id`. `subject_id` is a wire parameter naming a record the panel is about;
# unscoped, a stranger's id would be stored and their record's NAME rendered back in this user's
# hidden list. Each subject is looked up through a `current_user` relation, so a stranger's id is
# not found rather than found and refused — the same 404 every other owner id in this app gives.
class SuggestionDismissalsController < ApplicationController
  # WHERE EACH SUBJECT IS FOUND, one relation per class a suggestion's subject can be. The keys are
  # `SuggestionDismissal::SUBJECT_TYPES`, checked below before anything is looked up: `subject_type`
  # is a class name off the wire, and `params[:subject_type].constantize` is how a polymorphic
  # association becomes a class loader for whatever a crafted POST cares to name.
  #
  # `Budget.for_user` rather than an association, because a rule carries no `user_id` — it is owned
  # by a pool, which is owned by a user — and that scope is this app's one answer to which rules
  # are a user's.
  SUBJECT_SCOPES = {
    "Item" => ->(user) { user.items },
    "Category" => ->(user) { user.categories },
    "Budget" => ->(user) { Budget.for_user(user) }
  }.freeze

  # POST /suggestion_dismissals
  def create
    scope = SUBJECT_SCOPES[params[:subject_type]]
    return head :unprocessable_content if scope.nil?

    subject = scope.call(current_user).find(params[:subject_id])
    dismissal = current_user.suggestion_dismissals.new(subject: subject, kind: params[:kind])

    return redirect_to(budget_page_path, notice: "Hidden — it's under “hidden suggestions” at the foot of the panel.") if dismissal.save

    # A DUPLICATE IS NOT AN ERROR THE USER MADE. Two clicks on one button reach the uniqueness
    # validation, and the honest thing to say is that the suggestion is hidden — which it is —
    # rather than "Subject has already been taken" over a button that did what it promised.
    return redirect_to(budget_page_path, notice: "That one is already hidden.") if already_hidden?(dismissal)

    redirect_to budget_page_path, alert: "That suggestion couldn't be hidden — reload and try again."
  end

  # DELETE /suggestion_dismissals/:id
  #
  # Through the association, so a stranger's dismissal is not found. The row is the whole of what
  # is deleted: the suggestion comes back because the engine derives it again on the next load,
  # not because anything was restored.
  def destroy
    current_user.suggestion_dismissals.find(params[:id]).destroy
    redirect_to budget_page_path, notice: "Showing that suggestion again."
  end

  private

  # Whether the save failed ONLY because the row is already there. Asked of the errors rather than
  # by a second query: the uniqueness validation has just run, and re-asking the database would be
  # a second reader of the same question free to answer differently under a race.
  def already_hidden?(dismissal)
    dismissal.errors.of_kind?(:subject_id, :taken)
  end
end
