module UserAuthorization
  extend ActiveSupport::Concern

  # Override create to ensure the record belongs to the current user
  def create
    @record = resource_class.new(resource_params)
    authorize_record(@record)

    if @record.save
      respond_to do |format|
        format.html { redirect_to resource_path(@record), notice: "#{resource_name} was successfully created." }
        format.json { render :show, status: :created, location: @record }
      end
    else
      respond_to do |format|
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @record.errors, status: :unprocessable_entity }
      end
    end
  end

  # Override update to ensure the record belongs to the current user
  def update
    authorize_record(@record)

    if @record.update(resource_params)
      respond_to do |format|
        format.html { redirect_to resource_path(@record), notice: "#{resource_name} was successfully updated." }
        format.json { render :show, status: :ok, location: @record }
      end
    else
      respond_to do |format|
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @record.errors, status: :unprocessable_entity }
      end
    end
  end

  # Override destroy to ensure the record belongs to the current user
  def destroy
    authorize_record(@record)

    @record.destroy
    respond_to do |format|
      format.html { redirect_to resources_path, notice: "#{resource_name} was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Check if the record belongs to the current user
  def authorize_record(record)
    unless record.user == current_user
      flash[:alert] = "You don't have permission to #{action_name} this #{resource_name.downcase}."
      redirect_to resources_path and return
    end
  end
  
  # These methods should be implemented by the controller
  def resource_class
    controller_name.classify.constantize
  end
  
  def resource_name
    controller_name.singularize.humanize
  end
  
  def resources_path
    send("#{controller_name}_path")
  end
  
  def resource_path(record)
    send("#{controller_name.singularize}_path", record)
  end
  
  def resource_params
    # This should be overridden by the controller
    params.require(controller_name.singularize.to_sym).permit(permitted_attributes)
  end
  
  def permitted_attributes
    []
  end
end