class ModelsController < ApplicationController
  def index
    @models = Model.all.group_by(&:provider)
  end

  def show
    @model = Model.find(params[:id])
  end
end
