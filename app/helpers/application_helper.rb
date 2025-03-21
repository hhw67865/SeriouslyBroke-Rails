# frozen_string_literal: true

module ApplicationHelper
  include Heroicon::Engine.helpers

  def flash_class(flash_type)
    case flash_type.to_sym
    when :notice, :success
      "bg-status-success-light text-status-success"
    when :error, :alert
      "bg-status-danger-light text-status-danger"
    when :warning
      "bg-status-warning-light text-status-warning"
    else
      "bg-status-info-light text-status-info"
    end
  end

  def flash_icon(flash_type)
    case flash_type.to_sym
    when :notice, :success
      heroicon "check-circle", options: { class: "h-5 w-5" }
    when :error, :alert
      heroicon "x-circle", options: { class: "h-5 w-5" }
    when :warning
      heroicon "exclamation-triangle", options: { class: "h-5 w-5" }
    else
      heroicon "information-circle", options: { class: "h-5 w-5" }
    end
  end
end
