require 'rails_helper'

RSpec.describe Api::V1::RulesController, type: :controller do
  let(:category) { create(:category) }
  let(:valid_attributes) do
    {
      name: 'Test Rule',
      description: 'A test rule for specs',
      conditions: { 'description_contains' => [ 'test', 'sample' ] },
      actions: { 'set_category' => 'Test Category' },
      category_id: category.id,
      active: true
    }
  end

  let(:invalid_attributes) do
    {
      name: '',
      description: '',
      conditions: nil,
      actions: nil,
      category_id: nil
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

    context 'filtering by category' do
      let!(:grocery_category) { create(:category, :groceries) }
      let!(:transport_category) { create(:category, :transportation) }
      let!(:grocery_rule) { create(:rule, category: grocery_category) }
      let!(:transport_rule) { create(:rule, category: transport_category) }

      it 'filters by category name' do
        get :index, params: { category: 'Groceries' }
        json = JSON.parse(response.body)
        expect(json['rules'].length).to eq(1)
        expect(json['rules'].first['category_name']).to eq('Groceries')
      end

      it 'filters by category id' do
        get :index, params: { category_id: grocery_category.id }
        json = JSON.parse(response.body)
        expect(json['rules'].length).to eq(1)
        expect(json['rules'].first['category_id']).to eq(grocery_category.id)
      end
    end

    it 'includes category information' do
      get :index
      json = JSON.parse(response.body)
      rule_with_category = json['rules'].first
      expect(rule_with_category).to have_key('category_name')
      expect(rule_with_category).to have_key('category_id')
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

    it 'includes conditions and actions' do
      get :show, params: { id: rule.to_param }
      json = JSON.parse(response.body)
      expect(json['rule']['conditions']).to be_present
      expect(json['rule']['actions']).to be_present
    end

    it 'includes category information' do
      get :show, params: { id: rule.to_param }
      json = JSON.parse(response.body)
      expect(json['rule']['category_name']).to eq(rule.category.name)
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

      it 'properly stores JSON conditions and actions' do
        post :create, params: { rule: valid_attributes }
        json = JSON.parse(response.body)
        expect(json['rule']['conditions']).to eq(valid_attributes[:conditions])
        expect(json['rule']['actions']).to eq(valid_attributes[:actions])
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
        expect(response).to have_http_status(:unprocessable_entity)
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
          conditions: { 'amount_greater_than' => 100.0 },
          actions: { 'set_status' => 'flagged' }
        }
      end

      it 'updates the rule' do
        patch :update, params: { id: rule.to_param, rule: new_attributes }
        rule.reload
        expect(rule.name).to eq('Updated Rule')
        expect(rule.conditions).to eq(new_attributes[:conditions])
        expect(rule.actions).to eq(new_attributes[:actions])
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
        expect(response).to have_http_status(:unprocessable_entity)
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
    let!(:grocery_category) { create(:category, :groceries) }
    let!(:transport_category) { create(:category, :transportation) }
    let!(:grocery_rule) { create(:rule, :grocery_rule, category: grocery_category) }
    let!(:gas_rule) { create(:rule, :gas_station_rule, category: transport_category) }

    describe 'rule matching' do
      it 'can test if rules apply to sample transactions' do
        # This would require a custom endpoint or parameter
        # Testing the underlying logic through the model specs is sufficient
        expect(grocery_rule.applies_to?(build(:transaction, description: 'Grocery Store Purchase'))).to be true
        expect(gas_rule.applies_to?(build(:transaction, description: 'Shell Gas Station'))).to be true
      end
    end

    context 'rule statistics' do
      before do
        # Create transactions that would match rules
        create(:transaction, description: 'Grocery Store Purchase', category: grocery_category)
        create(:transaction, description: 'Supermarket Shopping', category: grocery_category)
        create(:transaction, description: 'Shell Gas Station', category: transport_category)
      end

      it 'includes rule usage statistics in listings' do
        # This would be a custom feature - for now we test basic functionality
        get :index
        json = JSON.parse(response.body)
        expect(json['rules']).to be_present
        expect(json['rules'].first).to have_key('active')
      end
    end
  end

  describe 'JSON serialization and complex conditions' do
    context 'with complex rule conditions' do
      let(:complex_rule) do
        create(:rule,
               conditions: {
                 'description_contains' => [ 'grocery', 'food', 'supermarket' ],
                 'amount_range' => { 'min' => 10.0, 'max' => 500.0 },
                 'exclude_descriptions' => [ 'gas', 'fuel' ]
               },
               actions: {
                 'set_category' => 'Groceries',
                 'set_status' => 'approved',
                 'add_note' => 'Auto-categorized as grocery purchase'
               })
      end

      it 'properly serializes complex conditions and actions' do
        get :show, params: { id: complex_rule.to_param }
        json = JSON.parse(response.body)

        expect(json['rule']['conditions']['description_contains']).to eq([ 'grocery', 'food', 'supermarket' ])
        expect(json['rule']['conditions']['amount_range']).to eq({ 'min' => 10.0, 'max' => 500.0 })
        expect(json['rule']['actions']['set_category']).to eq('Groceries')
      end
    end

    context 'with nested JSON structures' do
      let(:nested_rule) do
        create(:rule,
               conditions: {
                 'and' => [
                   { 'description_contains' => 'restaurant' },
                   { 'or' => [
                     { 'amount_greater_than' => 50.0 },
                     { 'time_range' => { 'start' => '18:00', 'end' => '23:00' } }
                   ] }
                 ]
               })
      end

      it 'handles nested JSON conditions correctly' do
        get :show, params: { id: nested_rule.to_param }
        json = JSON.parse(response.body)

        expect(json['rule']['conditions']['and']).to be_an(Array)
        expect(json['rule']['conditions']['and'].first['description_contains']).to eq('restaurant')
      end
    end
  end

  describe 'validation edge cases' do
    it 'validates JSON format for conditions' do
      post :create, params: {
        rule: valid_attributes.merge(conditions: 'invalid json string')
      }
      # This should be caught by our JSON column or validation
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'validates JSON format for actions' do
      post :create, params: {
        rule: valid_attributes.merge(actions: 'invalid json string')
      }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'requires at least one condition' do
      post :create, params: {
        rule: valid_attributes.merge(conditions: {})
      }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'requires at least one action' do
      post :create, params: {
        rule: valid_attributes.merge(actions: {})
      }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
