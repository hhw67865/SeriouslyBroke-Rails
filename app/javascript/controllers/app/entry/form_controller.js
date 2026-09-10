import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["itemSelect", "itemNameField", "categorySelect", "account"]
  static values = { incomeIds: Array }

  connect() {
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
      }
    })
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
