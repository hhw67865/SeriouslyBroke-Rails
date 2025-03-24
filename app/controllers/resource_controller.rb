class ResourceController < ApplicationController
  include UserAuthorization
  
  before_action :set_record, only: [:show, :edit, :update, :destroy]
  
  # GET /resources
  def index
    @records = current_user_records
  end

  # GET /resources/1
  def show
  end

  # GET /resources/new
  def new
    @record = resource_class.new
  end

  # GET /resources/1/edit
  def edit
  end

  private
  
  # Use callbacks to share common setup or constraints between actions.
  def set_record
    @record = current_user_records.find(params[:id])
  end
  
  def current_user_records
    # This finds records owned by the current user
    # Child controllers can override this to handle different ownership structures
    current_user.send(controller_name)
  end
end 