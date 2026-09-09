import { Controller } from "@hotwired/stimulus"

// Opening one category on the Budget page (two-shapes spec §4), and remembering which one.
//
// PROGRESSIVE ENHANCEMENT, EXACTLY AS THE REORDER BESIDE IT IS. Every chevron is already a link
// carrying `?open=<id>` (or bare `/budget` on the open row), so with scripting off the page works
// by round trip and nothing here is load-bearing. What this adds is the flip without one: the
// panels are all rendered and the closed ones carry `hidden`, so opening is a `hidden` attribute
// moving from one row to another.
//
// ** THE SERVER-RENDERED ONE WINS ON LOAD. ** A page that arrived with `?open=` — a link, a
// redirect after an adjustment, the categories page's suggestion pointer — is showing the category
// the user just asked for, and restoring localStorage over it would be the browser overruling the
// URL. So the memory is only consulted when the server opened nothing, and it is WRITTEN on every
// open either way.
//
// `localStorage` PER USER-AGENT, NOT PER USER, and the key says so: this is a convenience about
// where somebody was looking, not state the app owes anyone. It is wrapped because a browser with
// site data blocked THROWS on the accessor rather than answering null, and a Budget page that
// refused to render because a preference could not be read would be a real screen lost to an
// unreal one.
const MEMORY_KEY = "budget-page:open-category"

export default class extends Controller {
  static targets = ["row", "panel"]

  connect() {
    if (this.openRow) return this.remember(this.openRow.dataset.categoryId)

    const remembered = this.recall()
    if (remembered) this.open(remembered)
  }

  // The chevron's own click. `preventDefault` only once we are sure we can do the job here: a
  // click on a row this controller does not hold is left to the link, which is the same outcome
  // the no-JavaScript path gets.
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

  // ▾ CLOSED, ▴ OPEN, and `aria-expanded` with it — the glyph and the announced state are the same
  // fact, so a reader who cannot see the panel is told the same thing the arrow says.
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
