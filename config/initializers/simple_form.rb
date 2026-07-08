# frozen_string_literal: true

# Single source of truth for SimpleForm. All styling comes from the form
# component classes defined in app/assets/tailwind/application.css —
# views must not pass input_html/label_html classes for styling.
SimpleForm.setup do |config|
  config.wrappers :default, class: "w-full" do |b|
    b.use :html5
    b.use :placeholder
    b.optional :maxlength
    b.optional :minlength
    b.optional :pattern
    b.optional :min_max
    b.optional :readonly

    b.use :label, class: "form-label"
    b.use :input, class: "form-input", error_class: "form-input-error"
    b.use :hint, wrap_with: { tag: :p, class: "form-hint" }
    b.use :error, wrap_with: { tag: :p, class: "form-error" }
  end

  config.wrappers :select, class: "w-full" do |b|
    b.use :html5
    b.optional :readonly

    b.use :label, class: "form-label"
    b.use :input, class: "form-select", error_class: "form-input-error"
    b.use :hint, wrap_with: { tag: :p, class: "form-hint" }
    b.use :error, wrap_with: { tag: :p, class: "form-error" }
  end

  config.wrappers :textarea, class: "w-full" do |b|
    b.use :html5
    b.use :placeholder
    b.optional :maxlength
    b.optional :minlength

    b.use :label, class: "form-label"
    b.use :input, class: "form-textarea", error_class: "form-input-error"
    b.use :hint, wrap_with: { tag: :p, class: "form-hint" }
    b.use :error, wrap_with: { tag: :p, class: "form-error" }
  end

  config.wrappers :boolean, class: "w-full" do |b|
    b.use :html5
    b.optional :readonly

    b.wrapper class: "flex items-center gap-2" do |ba|
      ba.use :input, class: "form-checkbox"
      ba.use :label, class: "form-label mb-0 cursor-pointer select-none"
    end

    b.use :hint, wrap_with: { tag: :p, class: "form-hint" }
    b.use :error, wrap_with: { tag: :p, class: "form-error" }
  end

  config.default_wrapper = :default
  config.wrapper_mappings = {
    select: :select,
    text: :textarea,
    boolean: :boolean
  }

  config.boolean_style = :inline
  config.button_class = "btn btn-primary"
  config.error_notification_tag = :div
  config.error_notification_class = "bg-status-danger-light text-status-danger px-4 py-3 rounded mb-6 text-sm"
  config.collection_wrapper_tag = :div
  config.collection_wrapper_class = "grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-3"
  config.item_wrapper_tag = :div
  config.default_form_class = "space-y-6"
  config.browser_validations = false
  config.boolean_label_class = nil
  config.input_field_error_class = "form-input-error"
end
