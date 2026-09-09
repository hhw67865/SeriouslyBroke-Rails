import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["itemSelect", "itemNameField", "categorySelect"]

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
          // User created a new category - clear items
          this.updateItemSelect(null)
        } else {
          // User selected existing category - fetch its items
          this.fetchItemsForCategory(value)
        }

        // THE ONE CATEGORY-CHANGE HOOK ON THIS FORM, ANNOUNCED (spec §6). The envelope is derived
        // from the category and never picked, so the impact card has to follow this select — and
        // it follows it from HERE rather than by listening to the select itself, because a second
        // listener would be a second description of "the user picked a category", free to disagree
        // with this one about when that happened (TomSelect's own `change` on the hidden original
        // fires on paths this callback does not, clearing included).
        //
        // An event rather than a direct call: this controller owns the item list and knows nothing
        // about envelopes, and it should stay that way.
        this.dispatch("categoryChanged", { detail: { categoryId: value }, prefix: "entry" })
      }
    })
  }

  updateItemSelect(items) {
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
  }

  fetchItemsForCategory(categoryId) {
    fetch(`/categories/${categoryId}/items.json`)
      .then(response => response.json())
      .then(items => {
        this.updateItemSelect(items)
      })
      .catch(error => {
        console.error("Error fetching items:", error)
        this.updateItemSelect(null)
      })
  }
}