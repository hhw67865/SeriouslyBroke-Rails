import { Controller } from "@hotwired/stimulus"

// The impact card's live half: two figures come down in the card and this does one subtraction and
// one division with them. It re-derives no status — that answer lives on the server.
export default class extends Controller {
  static targets = ["card", "figures", "after", "bar", "overdraw", "amount", "submit"]
  static values = { url: String, entryId: String }

  // The same expression as `EntryImpactPresenter::TYPED_AMOUNT`: a formula (`10*5`) reads as
  // "nothing typed yet", because `parseFloat("10*5")` is 10 — wrong rather than absent.
  static TYPED_AMOUNT = /^\d*\.?\d+$/

  connect() {
    this.requestToken = 0
  }

  // Both callbacks route through #recompute, which reads the DOM itself: they fire in an order that
  // depends on how the browser batches one `innerHTML` write.
  figuresTargetConnected() {
    this.recompute()
  }

  figuresTargetDisconnected() {
    this.recompute()
  }

  // `input` is the keystroke and the calculator pad's own dispatch; `change` is what a value set
  // without keystrokes dispatches.
  recompute() {
    if (!this.hasFiguresTarget) {
      this.writeSubmit(false)
      return
    }

    const figures = this.figuresTarget
    const balance = this.cents(parseFloat(figures.dataset.balance))
    const denominator = this.cents(parseFloat(figures.dataset.denominator))
    const after = balance - this.cents(this.typedAmount())

    this.afterTarget.textContent = this.money(after)
    this.afterTarget.classList.toggle("text-status-danger", after < 0)
    // A category nothing claims has no bar at all — a real absence, not a defensive guard.
    if (this.hasBarTarget) this.barTarget.style.width = `${this.barPercent(after, denominator)}%`
    this.overdrawTarget.hidden = after >= 0
    this.writeSubmit(after < 0)
  }

  categoryChanged(event) {
    this.refresh(event.detail.categoryId)
  }

  // The typed amount travels with the request so the fragment is already correct for what is in the
  // box; the token guards a user clicking through four categories faster than the network answers.
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
        // Cleared rather than left standing: a card about the previous category answers the
        // question the user is asking with a figure about something else.
        if (token !== this.requestToken) return
        this.cardTarget.innerHTML = ""
        console.error("Error loading impact card:", error)
      })
  }

  // Both labels come down on the button itself. `value` for the `input type="submit"` simple_form
  // builds, `textContent` for a `<button>`.
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

  // `EntryImpactPresenter#bar_fraction` in the browser's own arithmetic. A zero denominator means
  // zero bar and never a division.
  barPercent(after, denominator) {
    if (denominator <= 0) return 0

    return Math.round(Math.min(Math.max(after / denominator, 0), 1) * 100)
  }

  // NaN in means zero out: `parseFloat("")` is NaN, and NaN cents would poison the card into "$NaN".
  cents(dollars) {
    return Number.isFinite(dollars) ? Math.round(dollars * 100) : 0
  }

  // `cents === 0 ? 0 : cents` normalises `-0`, which `Intl.NumberFormat` prints as "-$0.00"; the
  // sign of a real negative is the whole point of the overdraw state, so only the zero is touched.
  money(cents) {
    const safe = cents === 0 ? 0 : cents

    return new Intl.NumberFormat("en-US", { style: "currency", currency: "USD" }).format(safe / 100)
  }
}
