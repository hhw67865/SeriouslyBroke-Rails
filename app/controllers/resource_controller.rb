class ResourceController < ApplicationController
  include UserAuthorization
  
  before_action :set_resource, only: [:show, :edit, :update, :destroy]
  
  # GET /resources
  def index
    instance_variable_set("@#{controller_name}", current_user_records)
  end

  # GET /resources/1
  def show
  end

  # GET /resources/new
  def new
    instance_variable_set("@#{controller_name.singularize}", resource_class.new)
  end

  # GET /resources/1/edit
  def edit
  end

  private
  
  # Use callbacks to share common setup or constraints between actions.
  def set_resource
    instance_variable_set("@#{controller_name.singularize}", current_user_records.find(params[:id]))
  end
  
  def current_user_records
    # This finds records owned by the current user
    # Child controllers can override this to handle different ownership structures
    current_user.send(controller_name)
  end
end 