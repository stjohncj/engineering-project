class Api::V1::RulesController < ApplicationController
  before_action :set_rule, only: [:show, :update, :destroy]
  
  def index
    @rules = Rule.all.order(created_at: :desc)
    
    render json: {
      rules: @rules.map { |r| rule_json(r) }
    }
  end
  
  def show
    render json: { rule: rule_json(@rule) }
  end
  
  def create
    @rule = Rule.new(rule_params)
    
    if @rule.save
      render json: { rule: rule_json(@rule) }, status: :created
    else
      render json: { errors: @rule.errors.full_messages }, status: :unprocessable_entity
    end
  end
  
  def update
    if @rule.update(rule_params)
      render json: { rule: rule_json(@rule) }
    else
      render json: { errors: @rule.errors.full_messages }, status: :unprocessable_entity
    end
  end
  
  def destroy
    @rule.destroy
    head :no_content
  end
  
  private
  
  def set_rule
    @rule = Rule.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Rule not found" }, status: :not_found
  end
  
  def rule_params
    params.require(:rule).permit(:name, :condition_field, :condition_operator, :condition_value, :action_type, :action_value, :active)
  end
  
  def rule_json(rule)
    {
      id: rule.id,
      name: rule.name,
      condition_field: rule.condition_field,
      condition_operator: rule.condition_operator,
      condition_value: rule.condition_value,
      action_type: rule.action_type,
      action_value: rule.action_value,
      active: rule.active,
      created_at: rule.created_at,
      updated_at: rule.updated_at
    }
  end
end