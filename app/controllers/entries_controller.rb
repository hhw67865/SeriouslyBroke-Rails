class EntriesController < ResourceController
  private
  
    def resource_params
      params.require(:entry).permit(:amount, :date, :description, :item_id)
    end
end
