import { Controller } from "@hotwired/stimulus"

// THE §6 IMPACT CARD'S LIVE HALF: the "can I afford this" answer keeping up with the amount box.
//
// CLIENT-SIDE ARITHMETIC OVER FIGURES THE SERVER ALREADY PRINTED, and deliberately the smallest
// possible amount of it (plan decision 1). Two numbers come down in the card — the envelope's
// balance and what the bar measures against — and this controller does one subtraction and one
// division with them. It does NOT re-derive a status: `PoolStatus` is the app's most-guarded
// reader, it lives on the server, and a browser-side copy of it would be a second answer to the
// question every other screen asks of the first.
//
// NOTHING HERE IS PERSISTED and nothing here blocks. Overdrawing changes three things — the sign of
// one figure, the visibility of one sentence, and the words on the submit button — and every one of
// those states is rendered by the SERVER too (see `_impact.html.erb`), so this only ever toggles
// between two things the server would have said itself.
//
// CENTS AS INTEGERS, NEVER DOLLARS AS FLOATS, the same rule the sacrifice dial keeps: `0.1 + 0.2`
// is 0.30000000000000004, and a card whose whole job is to be believed cannot print that.
export default class extends Controller {
  static targets = ["card", "figures", "after", "bar", "buffer", "amount", "submit"]
  static values = { url: String, entryId: String }

  // WHAT COUNTS AS A TYPED AMOUNT — the same expression as `EntryImpactPresenter::TYPED_AMOUNT`,
  // and it must stay that way or the card would say one thing on arrival and another after a
  // keystroke that changed nothing.
  //
  // The amount box accepts a FORMULA (`10*5`), which Dentaku evaluates on the server at save time.
  // There is no Dentaku here, and `parseFloat("10*5")` is 10 — a figure that is WRONG rather than
  // absent, which is the worse of the two failures. So a formula reads as "nothing typed yet" and
  // the card holds at the balance until it resolves into a plain number. A leading minus and a
  // thousands separator fall out of the same test, for the same reason: neither is an amount this
  // form can save.
  static TYPED_AMOUNT = /^\d*\.?\d+$/

  connect() {
    this.requestToken = 0
  }

  // The card is replaced wholesale when the category changes, so the arithmetic re-runs off
  // whatever is on screen NOW rather than off anything cached at connect. Both callbacks route
  // through #recompute, which reads the DOM itself: the two fire in an order that depends on how
  // the browser batches one `innerHTML` write, and a reset that depended on which came last would
  // be a coin toss.
  figuresTargetConnected() {
    this.recompute()
  }

  figuresTargetDisconnected() {
    this.recompute()
  }

  // `input` AND `change`. `input` is the keystroke and the calculator pad's own dispatch
  // (`shared--calculator-pad#setValue` fires it after every key); `change` is what a value set
  // WITHOUT keystrokes dispatches — the shape the sacrifice dial's close-out measured on this
  // branch — and a card that only listened for the first would sit on a stale figure for it.
  recompute() {
    if (!this.hasFiguresTarget) {
      this.writeSubmit(false)
      return
    }

    const figures = this.figuresTarget
    const balance = this.cents(parseFloat(figures.dataset.balance))
    const denominator = this.cents(parseFloat(figures.dataset.denominator))
    // The ledger's own sign for this entry's category: a savings contribution RAISES the pool it
    // fills. Read off the card rather than decided here — which way money moves is the server's
    // fact about a category type, not the browser's guess.
    const direction = Number(figures.dataset.direction)
    const after = balance + direction * this.cents(this.typedAmount())

    this.afterTarget.textContent = this.money(after)
    this.afterTarget.classList.toggle("text-status-danger", after < 0)
    this.barTarget.style.width = `${this.barPercent(after, denominator)}%`
    this.bufferTarget.hidden = after >= 0
    this.writeSubmit(after < 0)
  }

  // THE CATEGORY CHANGED, so the card describes a different envelope — or none.
  //
  // ONE CATEGORY-CHANGE HOOK IN THE FORM, EXTENDED. `app--entry--form` already owns the TomSelect
  // `onChange` that refetches the item list; it now announces the change and this controller
  // answers it. A second listener on the same select would be a second description of "the user
  // picked a category", free to disagree with the first about when that happened.
  //
  // THE SERVER RENDERS THE NEW CARD. Every branch the card has — the honest no-envelope card, the
  // goal shape, the date's absence for an undeclared user — is a server decision, and re-deciding
  // them here would put the whole of `_impact.html.erb` in JavaScript beside itself.
  categoryChanged(event) {
    this.refresh(event.detail.categoryId)
  }

  // The typed amount travels WITH the request so the fragment that comes back is already correct
  // for what is in the box. It is recomputed the moment the card lands anyway (see
  // #figuresTargetConnected), but a fragment that was momentarily wrong is a fragment that cannot
  // be tested on its own.
  //
  // The token guards the obvious race: a user clicking through four categories gets four responses
  // in whatever order the network returns them, and the last card to ARRIVE is not necessarily the
  // last one ASKED for.
  refresh(categoryId) {
    const token = ++this.requestToken
    const url = new URL(this.urlValue, window.location.origin)
    url.searchParams.set("category_id", categoryId || "")
    url.searchParams.set("amount", this.hasAmountTarget ? this.amountTarget.value : "")
    if (this.entryIdValue) url.searchParams.set("entry_id", this.entryIdValue)

    fetch(url, { headers: { Accept: "text/html" } })
      .then((response) => response.text())
      .then((html) => {
        if (token !== this.requestToken) return
        this.cardTarget.innerHTML = html
      })
      .catch((error) => {
        // The card is cleared rather than left standing: a card describing the PREVIOUS category
        // is worse than no card, because it answers the question the user is asking with a figure
        // about something else.
        if (token !== this.requestToken) return
        this.cardTarget.innerHTML = ""
        console.error("Error loading envelope impact:", error)
      })
  }

  // §6: "The button reads 'Save anyway'." Both labels come down on the button itself, so the words
  // are the server's either way and this only chooses between them. `value` for the
  // `input type="submit"` simple_form builds, `textContent` for a `<button>` — the form's submit is
  // the first today and one refactor from being the second.
  writeSubmit(overdrawn) {
    if (!this.hasSubmitTarget) return

    const button = this.submitTarget
    const label = overdrawn ? button.dataset.overdrawnLabel : button.dataset.defaultLabel
    if (button.tagName === "INPUT") {
      button.value = label
    } else {
      button.textContent = label
    }
  }

  typedAmount() {
    const raw = this.hasAmountTarget ? this.amountTarget.value.trim() : ""

    return this.constructor.TYPED_AMOUNT.test(raw) ? Number(raw) : 0
  }

  // BALANCE-AFTER OVER WHAT THE ENVELOPE IS FOR, clamped 0..1 — `EntryImpactPresenter#bar_fraction`
  // in the browser's own arithmetic. Zero denominator means zero bar and never a division: an
  // envelope with no rules on it has no per-period claim for a bar to be a fraction OF.
  barPercent(after, denominator) {
    if (denominator <= 0) return 0

    return Math.round(Math.min(Math.max(after / denominator, 0), 1) * 100)
  }

  // NaN in means zero out, and the reachable shape is an empty box: `parseFloat("")` is NaN, and
  // NaN cents would poison the card into "$NaN".
  cents(dollars) {
    return Number.isFinite(dollars) ? Math.round(dollars * 100) : 0
  }

  // Formatted to match `number_to_currency`, which printed every figure on this card on the way
  // down — a live figure reading "185" beside a server figure reading "$185.00" is two vocabularies
  // for one number.
  //
  // `cents === 0 ? 0 : cents` AND NOT `Math.abs`, because BOTH halves of that are load-bearing here.
  // Negative zero is reachable — `Math.round(-0.4)` is `-0`, and so is a balance spent to the exact
  // penny through the wrong rounding — and `Intl.NumberFormat().format(-0)` is "-$0.00", which is
  // the sacrifice dial's exact shipped bug: the one keystroke that lands an envelope precisely
  // level printed a negative. `Math.abs` was the fix THERE because that figure is never negative;
  // here the sign is the whole point of the overdraw state, so only the zero is normalised.
  money(cents) {
    const safe = cents === 0 ? 0 : cents

    return new Intl.NumberFormat("en-US", { style: "currency", currency: "USD" }).format(safe / 100)
  }
}
