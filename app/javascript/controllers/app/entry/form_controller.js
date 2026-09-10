import { Controller } from "@hotwired/stimulus"

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

export default class extends Controller {
  static targets = ["itemSelect", "itemNameField", "categorySelect", "account", "amount", "amountHint"]
  static values = { incomeIds: Array }

  connect() {
    this.itemsById = new Map()
    this.initializeItemSelect()
    this.initializeCategorySelect()
  }

  initializeItemSelect() {
    this.itemSelect = new TomSelect(this.itemSelectTarget, {
      create: (input) => {
        return { text: input, value: input, is_new: true }
      },
      onChange: (value) => {
        const item = this.itemSelect.options[value]
        if (item && item.is_new) {
          this.itemNameFieldTarget.value = item.text
        } else {
          this.itemNameFieldTarget.value = ""
        }
        this.fillAmountFromHistory(value)
      }
    })
  }

  // An empty field only: a value already on the page is the user's, not the item's history's.
  fillAmountFromHistory(itemId) {
    const item = this.itemsById.get(itemId)
    if (!this.hasAmountTarget || !item || !item.last_amount || this.amountTarget.value !== "") return

    this.amountTarget.value = item.last_amount
    this.amountHintTarget.textContent = `Filled from the last time: $${item.last_amount} on ${this.formatDate(item.last_date)}.`
    this.amountHintTarget.hidden = false
  }

  hideAmountHint() {
    if (this.hasAmountHintTarget) this.amountHintTarget.hidden = true
  }

  // Read as plain digits, never through Date parsing, so a viewer's timezone can't shift the day.
  formatDate(iso) {
    const [, month, day] = iso.split("-").map(Number)
    return `${MONTHS[month - 1]} ${day}`
  }

  initializeCategorySelect() {
    this.categorySelect = new TomSelect(this.categorySelectTarget, {
      onChange: (value) => {
        if (value === "") {
          this.updateItemSelect(null, "")
        } else {
          this.fetchItemsForCategory(value)
        }

        this.toggleAccount(value)

        // The one category-change hook on this form: a second listener on the select itself would
        // be free to disagree with this one about when the user picked a category.
        this.dispatch("categoryChanged", { detail: { categoryId: value }, prefix: "entry" })
      }
    })
  }

  // Only income is asked which account it landed in. The ids come down from the server rather than
  // being read off the optgroup labels, which are display strings.
  toggleAccount(categoryId) {
    if (!this.hasAccountTarget) return

    this.accountTarget.hidden = !this.incomeIdsValue.includes(categoryId)
  }

  updateItemSelect(items, categoryId) {
    if (this.itemSelect) {
      this.itemSelect.destroy()
    }

    this.itemsById = new Map((items || []).map(item => [String(item.id), item]))

    if (items === null) {
      this.itemSelectTarget.innerHTML = '<option value="">Create an item</option>'
    } else {
      this.itemSelectTarget.innerHTML = '<option value="">Select or Create an item</option>' +
        items.map(item => `<option value="${item.id}">${item.name}</option>`).join('')
    }

    this.initializeItemSelect()
    // Whose list is on screen. The rebuild replaces this control, so anything that reaches for it
    // between the category change and the fetch landing reaches for an element about to be thrown
    // away; this says when that is over.
    const wrapper = this.itemSelectTarget.closest(".ts-wrapper") || this.itemSelectTarget
    wrapper.dataset.itemsLoaded = categoryId
  }

  fetchItemsForCategory(categoryId) {
    fetch(`/categories/${categoryId}/items.json`)
      .then(response => response.json())
      .then(items => {
        this.updateItemSelect(items, categoryId)
      })
      .catch(error => {
        console.error("Error fetching items:", error)
        this.updateItemSelect(null, categoryId)
      })
  }
}
