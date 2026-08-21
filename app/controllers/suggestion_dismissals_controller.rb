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

  # A DUPLICATE IS NOT AN ERROR THE USER MADE, and this sentence is said from TWO places — the
  # validation's refusal and the index's — so it is spelled once. Both mean the same thing to the
  # person who pressed the button: the suggestion is hidden, which is what they asked for.
  ALREADY_HIDDEN = "That one is already hidden."

  # POST /suggestion_dismissals
  #
  # THE `RecordNotUnique` RESCUE IS THE OTHER HALF OF THE LATCH. The migration calls the unique
  # index the real guard and the validation the thing in front of it — but a validation cannot stop
  # two requests that both read "not there" in the same instant, and without this the loser of that
  # race reaches the user as a 500 on a button that did exactly what it promised. The redirect is
  # the same one the validation produces, because the OUTCOME is the same: the row is there now.
  def create
    subject = scoped_subject
    return head :unprocessable_content if subject.nil?

    dismissal = current_user.suggestion_dismissals.new(subject: subject, kind: params[:kind])
    redirect_to budget_page_path, **outcome_of(dismissal)
  rescue ActiveRecord::RecordNotUnique
    redirect_to budget_page_path, notice: ALREADY_HIDDEN
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

  # THE RECORD THIS DISMISSAL IS ABOUT, looked up through `current_user`, or nil where the wire
  # named a class no suggestion carries.
  #
  # THE TWO REFUSALS ARE DIFFERENT AND STAY DIFFERENT. An unanswerable `subject_type` is nil here
  # and becomes a 422 — the request is malformed, and there is no record to have or not have. A
  # `subject_id` that is not this user's raises `RecordNotFound` from `find` and becomes the same
  # 404 every other owner id in this app gives, which is what keeps a stranger's record from being
  # distinguishable from one that does not exist.
  def scoped_subject
    scope = SUBJECT_SCOPES[params[:subject_type]]

    scope&.call(current_user)&.find(params[:subject_id])
  end

  # WHAT TO SAY, as the flash pair `redirect_to` takes. Split out of #create so that action reads
  # as its three steps (find the subject, build the row, answer) rather than carrying the branch
  # as well — which is what put it over `Metrics/AbcSize`.
  def outcome_of(dismissal)
    return { notice: "Hidden — it's under “hidden suggestions” at the foot of the panel." } if dismissal.save
    return { notice: ALREADY_HIDDEN } if already_hidden?(dismissal)

    { alert: "That suggestion couldn't be hidden — reload and try again." }
  end

  # Whether the save failed ONLY because the row is already there. Asked of the errors rather than
  # by a second query: the uniqueness validation has just run, and re-asking the database would be
  # a second reader of the same question free to answer differently under a race.
  def already_hidden?(dismissal)
    dismissal.errors.of_kind?(:subject_id, :taken)
  end
end
