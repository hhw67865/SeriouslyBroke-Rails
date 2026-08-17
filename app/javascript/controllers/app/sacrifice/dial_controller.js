import { Controller } from "@hotwired/stimulus"

// THE WHAT-IF DIAL (spec §9): "the running total updates live, so what do I sacrifice is dialled
// in rather than computed".
//
// CLIENT-SIDE ARITHMETIC OVER FIGURES THE SERVER ALREADY PRINTED. No request, no persistence
// (plan decision 3) — every number this touches came down in the page and every number it writes
// goes back into the page. The user can reload out of any state they dial in, which is the point:
// nothing here is a decision, it is a question.
//
// IT WORKS IN PER-PERIOD UNITS THROUGHOUT, AND THAT IS THE WHOLE OF ITS CORRECTNESS. Every row's
// `data-claim` is `Budget#steady_ask` — what the rule claims from ONE period — never
// `budget.amount`, which is the rule's own unit: a $1,500 monthly Rent rule claims $692.31 from a
// biweekly period, and a dial fed sticker prices would free $1,500 out of a $2,400 paycheck by
// touching one rule. The amount input types against the per-period figure too, and the row says so
// beside it, because the edit form this row links to works in the rule's OWN unit and the two
// screens must not be confused. The mixed-unit slip has struck five times on this branch.
//
// CENTS AS INTEGERS, NEVER DOLLARS AS FLOATS. `0.1 + 0.2` is 0.30000000000000004, and a page whose
// total is a sum over sixteen rows would show it: the demo's cuttable rules include $92.31 and
// $6.92, and floating dollars put "$1,364.99" and "$1,365.01" one keystroke apart. Everything is
// rounded to cents on the way in, added as integers, and formatted once on the way out.
export default class extends Controller {
  static targets = ["row", "toggle", "amount", "rowFrees", "freed", "verdict"]
  // Dollars on the attribute (that is what the server prints), cents inside — see #cents.
  static values = { gap: Number }

  connect() {
    this.recompute()
  }

  // Rows are read out of the DOM every time rather than cached at connect: the page is
  // server-rendered and static, but a cache would be one more description of "what is on screen"
  // free to disagree with the screen itself.
  recompute() {
    let freed = 0

    this.rowTargets.forEach((row) => {
      const rowFreed = this.freedBy(row)
      freed += rowFreed
      this.freesFieldFor(row).textContent = this.money(rowFreed)
    })

    this.freedTarget.textContent = this.money(freed)
    this.writeVerdict(this.cents(this.gapValue) - freed)
  }

  // WHAT CUTTING THIS ROW TO THE TYPED FIGURE WOULD FREE, in cents.
  //
  // Cutting TO a figure, so this is `claim - typed` — and it is clamped into [0, claim] at both
  // ends. Typing MORE than the rule already claims is not a cut and must free nothing (the floor);
  // typing a negative is not a rule anyone could write, and Budget's own validation refuses one
  // (the ceiling, which is what an empty field lands on).
  //
  // An unchecked row frees nothing whatever is typed in it, because the checkbox is the sentence:
  // "I am cutting this". The field stays enabled so a user can dial a figure before committing to
  // the row, and the row's own "frees" reads $0.00 until they do.
  freedBy(row) {
    const toggle = this.fieldFor(row, "toggle")
    if (!toggle.checked) return 0

    const claim = this.cents(parseFloat(row.dataset.claim))
    const typed = this.cents(parseFloat(this.fieldFor(row, "amount").value))

    return Math.min(Math.max(claim - typed, 0), claim)
  }

  // POSITIVE MEANS STILL SHORT. The unwinnable statement at the top of the page is the server's
  // (it is a fact about the rules, not about what is dialled); this is the live half, and it must
  // be able to say the same thing — a user who checks every box on an unwinnable budget lands here
  // with a positive remainder and reads it, rather than watching the total stop short with no
  // explanation.
  writeVerdict(remaining) {
    this.verdictTarget.textContent =
      remaining > 0
        ? `Still underwater ${this.money(remaining)} a period`
        : `Covered — ${this.money(-remaining)} a period to spare`
    this.verdictTarget.classList.toggle("text-status-danger", remaining > 0)
    this.verdictTarget.classList.toggle("text-status-success", remaining <= 0)
  }

  // Scoped to the row, never `this.<name>Targets[index]`: the target arrays are document-ordered
  // and a row with no amount field — a fixed rule, if one ever joined this list — would slide every
  // later row's figure onto the wrong rule, silently.
  fieldFor(row, name) {
    return row.querySelector(`[data-${this.identifier}-target="${name}"]`)
  }

  freesFieldFor(row) {
    return this.fieldFor(row, "rowFrees")
  }

  // NaN in means zero out, and the reachable shape is an empty field: `parseFloat("")` is NaN, and
  // NaN cents would poison the whole total into "$NaN". Zero is also the honest reading of a
  // cleared "cut to" box — the user has typed no floor, and #freedBy clamps the result to the
  // rule's own claim, so an empty field frees the rule entirely rather than an arbitrary amount.
  cents(dollars) {
    return Number.isFinite(dollars) ? Math.round(dollars * 100) : 0
  }

  // Formatted to match `number_to_currency`, which prints every other figure on this page — a dial
  // reading "1365" beside a server figure reading "$1,365.00" is two vocabularies for one number.
  money(cents) {
    return new Intl.NumberFormat("en-US", { style: "currency", currency: "USD" }).format(cents / 100)
  }
}
