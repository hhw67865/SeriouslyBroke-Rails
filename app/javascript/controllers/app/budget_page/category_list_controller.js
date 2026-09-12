import { Controller } from "@hotwired/stimulus"

// Opening one category, and remembering which one. Every chevron is already a link carrying
// `?open=<id>`, so this only saves the round trip — and a server-opened row wins over the memory.
const MEMORY_KEY = "budget-page:open-category"

export default class extends Controller {
  static targets = ["row", "panel"]

  connect() {
    if (this.openRow) return this.remember(this.openRow.dataset.categoryId)

    const remembered = this.recall()
    if (remembered) this.open(remembered)
  }

  // `preventDefault` only once we are sure we can do the job here: a click on a row this
  // controller does not hold is left to the link, which is the no-JavaScript path's own outcome.
  toggle(event) {
    const row = event.currentTarget.closest("[data-category-id]")
    if (!row) return

    event.preventDefault()
    const id = row.dataset.categoryId
    const wasOpen = !this.panelIn(row).hidden

    this.close()
    if (wasOpen) return this.remember(null)

    this.open(id)
  }

  // A click anywhere on the header opens the row, except on the arrows or another control, which
  // keep their own job. The chevron stays the control a keyboard or a reader reaches.
  toggleFromHeader(event) {
    if (event.target.closest("a, button, form, [data-category-toggle]")) return

    const chevron = event.currentTarget.querySelector("[data-category-toggle]")
    if (chevron) chevron.click()
  }

  open(id) {
    const row = this.rowFor(id)
    if (!row) return this.remember(null)

    this.panelIn(row).hidden = false
    this.markChevron(row, true)
    this.remember(id)
  }

  close() {
    this.rowTargets.forEach((row) => {
      this.panelIn(row).hidden = true
      this.markChevron(row, false)
    })
  }

  // ▾ closed, ▴ open, and `aria-expanded` with it — the glyph and the announced state are the same
  // fact, so a reader who cannot see the panel is told what the arrow says.
  markChevron(row, expanded) {
    const chevron = row.querySelector("[data-category-toggle]")
    if (!chevron) return

    chevron.setAttribute("aria-expanded", String(expanded))
    const glyph = chevron.querySelector("span")
    if (glyph) glyph.textContent = expanded ? "▴" : "▾"
  }

  rowFor(id) {
    return this.rowTargets.find((row) => row.dataset.categoryId === id)
  }

  panelIn(row) {
    return this.panelTargets.find((panel) => row.contains(panel))
  }

  get openRow() {
    return this.rowTargets.find((row) => !this.panelIn(row).hidden)
  }

  remember(id) {
    try {
      if (id) localStorage.setItem(MEMORY_KEY, id)
      else localStorage.removeItem(MEMORY_KEY)
    } catch {
      // Storage blocked. The page is already correct without it.
    }
  }

  recall() {
    try {
      return localStorage.getItem(MEMORY_KEY)
    } catch {
      return null
    }
  }
}
