require 'rails_helper'

RSpec.describe Api::V1::RulesController, type: :controller do
  let(:category) { create(:category) }
  let(:valid_attributes) do
    {
      name: 'Test Rule',
      condition_field: 'description',
      condition_operator: 'contains',
      condition_value: 'test',
      action_type: 'categorize',
      action_value: 'Test Category',
      active: true
    }
  end

  let(:invalid_attributes) do
    {
      name: '',
      condition_field: '',
      condition_operator: 'invalid',
      condition_value: '',
      action_type: 'invalid',
      action_value: ''
    }
  end

  describe 'GET #index' do
    let!(:rules) { create_list(:rule, 3) }
    let!(:inactive_rule) { create(:rule, :inactive) }

    it 'returns a success response' do
      get :index
      expect(response).to be_successful
    end

    it 'returns all rules by default' do
      get :index
      json = JSON.parse(response.body)
      expect(json['rules'].length).to eq(4)
    end

    context 'filtering by status' do
      it 'returns only active rules when requested' do
        get :index, params: { active: true }
        json = JSON.parse(response.body)
        expect(json['rules'].length).to eq(3)
        expect(json['rules'].all? { |r| r['active'] }).to be true
      end

      it 'returns only inactive rules when requested' do
        get :index, params: { active: false }
        json = JSON.parse(response.body)
        expect(json['rules'].length).to eq(1)
        expect(json['rules'].all? { |r| !r['active'] }).to be true
      end
    end

    it 'includes rule information' do
      get :index
      json = JSON.parse(response.body)
      rule_json = json['rules'].first
      expect(rule_json).to have_key('id')
      expect(rule_json).to have_key('name')
      expect(rule_json).to have_key('condition_field')
      expect(rule_json).to have_key('condition_operator')
      expect(rule_json).to have_key('condition_value')
      expect(rule_json).to have_key('action_type')
      expect(rule_json).to have_key('action_value')
      expect(rule_json).to have_key('active')
    end
  end

  describe 'GET #show' do
    let!(:rule) { create(:rule, :grocery_rule) }

    it 'returns a success response' do
      get :show, params: { id: rule.to_param }
      expect(response).to be_successful
    end

    it 'returns the rule' do
      get :show, params: { id: rule.to_param }
      json = JSON.parse(response.body)
      expect(json['rule']['id']).to eq(rule.id)
      expect(json['rule']['name']).to eq(rule.name)
    end

    it 'includes rule details' do
      get :show, params: { id: rule.to_param }
      json = JSON.parse(response.body)
      expect(json['rule']['condition_field']).to be_present
      expect(json['rule']['condition_operator']).to be_present
      expect(json['rule']['condition_value']).to be_present
      expect(json['rule']['action_type']).to be_present
      expect(json['rule']['action_value']).to be_present
    end

    it 'returns 404 for non-existent rule' do
      get :show, params: { id: 'nonexistent' }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST #create' do
    context 'with valid parameters' do
      it 'creates a new Rule' do
        expect {
          post :create, params: { rule: valid_attributes }
        }.to change(Rule, :count).by(1)
      end

      it 'returns a created response' do
        post :create, params: { rule: valid_attributes }
        expect(response).to have_http_status(:created)
      end

      it 'returns the created rule' do
        post :create, params: { rule: valid_attributes }
        json = JSON.parse(response.body)
        expect(json['rule']['name']).to eq('Test Rule')
        expect(json['rule']['active']).to be true
      end

      it 'properly stores rule attributes' do
        post :create, params: { rule: valid_attributes }
        json = JSON.parse(response.body)
        expect(json['rule']['condition_field']).to eq('description')
        expect(json['rule']['condition_operator']).to eq('contains')
        expect(json['rule']['condition_value']).to eq('test')
        expect(json['rule']['action_type']).to eq('categorize')
        expect(json['rule']['action_value']).to eq('Test Category')
      end
    end

    context 'with invalid parameters' do
      it 'does not create a new Rule' do
        expect {
          post :create, params: { rule: invalid_attributes }
        }.not_to change(Rule, :count)
      end

      it 'returns an unprocessable entity response' do
        post :create, params: { rule: invalid_attributes }
        expect(response).to have_http_status(:unprocessable_content)
      end

      it 'returns error messages' do
        post :create, params: { rule: invalid_attributes }
        json = JSON.parse(response.body)
        expect(json).to have_key('errors')
        expect(json['errors']['name']).to include("can't be blank")
      end
    end

    context 'with duplicate name' do
      before { create(:rule, name: 'Duplicate Rule') }

      it 'does not create a duplicate rule' do
        expect {
          post :create, params: { rule: valid_attributes.merge(name: 'Duplicate Rule') }
        }.not_to change(Rule, :count)
      end

      it 'returns validation error' do
        post :create, params: { rule: valid_attributes.merge(name: 'Duplicate Rule') }
        json = JSON.parse(response.body)
        expect(json['errors']['name']).to include('has already been taken')
      end
    end
  end

  describe 'PATCH #update' do
    let!(:rule) { create(:rule) }

    context 'with valid parameters' do
      let(:new_attributes) do
        {
          name: 'Updated Rule',
          condition_field: 'amount',
          condition_operator: 'greater_than',
          condition_value: '100.0',
          action_type: 'flag',
          action_value: 'Large transaction'
        }
      end

      it 'updates the rule' do
        patch :update, params: { id: rule.to_param, rule: new_attributes }
        rule.reload
        expect(rule.name).to eq('Updated Rule')
        expect(rule.condition_field).to eq('amount')
        expect(rule.condition_operator).to eq('greater_than')
        expect(rule.condition_value).to eq('100.0')
        expect(rule.action_type).to eq('flag')
        expect(rule.action_value).to eq('Large transaction')
      end

      it 'returns a success response' do
        patch :update, params: { id: rule.to_param, rule: new_attributes }
        expect(response).to be_successful
      end

      it 'can toggle active status' do
        patch :update, params: { id: rule.to_param, rule: { active: false } }
        rule.reload
        expect(rule.active).to be false
      end
    end

    context 'with invalid parameters' do
      it 'returns an unprocessable entity response' do
        patch :update, params: { id: rule.to_param, rule: invalid_attributes }
        expect(response).to have_http_status(:unprocessable_content)
      end

      it 'does not update the rule' do
        original_name = rule.name
        patch :update, params: { id: rule.to_param, rule: invalid_attributes }
        rule.reload
        expect(rule.name).to eq(original_name)
      end
    end
  end

  describe 'DELETE #destroy' do
    let!(:rule) { create(:rule) }

    it 'destroys the requested rule' do
      expect {
        delete :destroy, params: { id: rule.to_param }
      }.to change(Rule, :count).by(-1)
    end

    it 'returns no content response' do
      delete :destroy, params: { id: rule.to_param }
      expect(response).to have_http_status(:no_content)
    end

    it 'returns 404 for non-existent rule' do
      delete :destroy, params: { id: 'nonexistent' }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'rule testing and application' do
    let!(:grocery_rule) { create(:rule, :grocery_rule) }
    let!(:gas_rule) { create(:rule, :gas_station_rule) }

    describe 'rule matching' do
      it 'can test if rules apply to sample transactions' do
        # Testing the underlying logic through the model specs is sufficient
        expect(grocery_rule.applies_to?(build(:transaction, description: 'Grocery Store Purchase'))).to be true
        expect(gas_rule.applies_to?(build(:transaction, description: 'Shell Gas Station'))).to be true
      end
    end

    context 'rule statistics' do
      it 'includes rule basic information in listings' do
        get :index
        json = JSON.parse(response.body)
        expect(json['rules']).to be_present
        expect(json['rules'].first).to have_key('active')
        expect(json['rules'].first).to have_key('condition_field')
        expect(json['rules'].first).to have_key('action_type')
      end
    end
  end

  describe 'JSON serialization' do
    context 'with rule attributes' do
      let(:rule) { create(:rule, :grocery_rule) }

      it 'properly serializes rule attributes' do
        get :show, params: { id: rule.to_param }
        json = JSON.parse(response.body)

        expect(json['rule']['condition_field']).to eq('description')
        expect(json['rule']['condition_operator']).to eq('contains')
        expect(json['rule']['condition_value']).to eq('grocery')
        expect(json['rule']['action_type']).to eq('categorize')
        expect(json['rule']['action_value']).to eq('Groceries')
      end
    end
  end

  describe 'validation edge cases' do
    it 'validates field inclusion for condition_field' do
      post :create, params: {
        rule: valid_attributes.merge(condition_field: 'invalid_field')
      }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'validates operator inclusion for condition_operator' do
      post :create, params: {
        rule: valid_attributes.merge(condition_operator: 'invalid_operator')
      }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'validates action_type inclusion' do
      post :create, params: {
        rule: valid_attributes.merge(action_type: 'invalid_action')
      }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
