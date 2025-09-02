require 'rails_helper'

RSpec.describe Api::V1::CategoriesController, type: :controller do
  let(:valid_attributes) do
    {
      name: 'Test Category',
      description: 'A test category for specs'
    }
  end

  let(:invalid_attributes) do
    {
      name: '',
      description: 'Invalid category'
    }
  end

  describe 'GET #index' do
    let!(:categories) { create_list(:category, 3) }

    it 'returns a success response' do
      get :index
      expect(response).to be_successful
    end

    it 'returns all categories' do
      get :index
      json = JSON.parse(response.body)
      expect(json['categories'].length).to eq(3)
    end

    it 'includes transaction count for each category' do
      category = categories.first
      create_list(:transaction, 2, category: category)

      get :index
      json = JSON.parse(response.body)
      category_json = json['categories'].find { |c| c['id'] == category.id }
      expect(category_json['transaction_count']).to eq(2)
    end

    it 'orders categories by name' do
      create(:category, name: 'Zebra Category')
      create(:category, name: 'Alpha Category')

      get :index
      json = JSON.parse(response.body)
      names = json['categories'].map { |c| c['name'] }
      expect(names).to eq(names.sort)
    end
  end

  describe 'GET #show' do
    let!(:category) { create(:category) }

    it 'returns a success response' do
      get :show, params: { id: category.to_param }
      expect(response).to be_successful
    end

    it 'returns the category' do
      get :show, params: { id: category.to_param }
      json = JSON.parse(response.body)
      expect(json['category']['id']).to eq(category.id)
      expect(json['category']['name']).to eq(category.name)
    end

    it 'includes associated transactions' do
      transaction = create(:transaction, category: category)
      get :show, params: { id: category.to_param }
      json = JSON.parse(response.body)
      expect(json['category']['transactions']).to be_present
      expect(json['category']['transactions'].first['id']).to eq(transaction.id)
    end

    it 'returns 404 for non-existent category' do
      get :show, params: { id: 'nonexistent' }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST #create' do
    context 'with valid parameters' do
      it 'creates a new Category' do
        expect {
          post :create, params: { category: valid_attributes }
        }.to change(Category, :count).by(1)
      end

      it 'returns a created response' do
        post :create, params: { category: valid_attributes }
        expect(response).to have_http_status(:created)
      end

      it 'returns the created category' do
        post :create, params: { category: valid_attributes }
        json = JSON.parse(response.body)
        expect(json['category']['name']).to eq('Test Category')
        expect(json['category']['description']).to eq('A test category for specs')
      end
    end

    context 'with invalid parameters' do
      it 'does not create a new Category' do
        expect {
          post :create, params: { category: invalid_attributes }
        }.not_to change(Category, :count)
      end

      it 'returns an unprocessable entity response' do
        post :create, params: { category: invalid_attributes }
        expect(response).to have_http_status(:unprocessable_content)
      end

      it 'returns error messages' do
        post :create, params: { category: invalid_attributes }
        json = JSON.parse(response.body)
        expect(json).to have_key('errors')
        expect(json['errors']['name']).to include("can't be blank")
      end
    end

    context 'with duplicate name' do
      before { create(:category, name: 'Duplicate Name') }

      it 'does not create a duplicate category' do
        expect {
          post :create, params: { category: { name: 'Duplicate Name' } }
        }.not_to change(Category, :count)
      end

      it 'returns validation error' do
        post :create, params: { category: { name: 'Duplicate Name' } }
        json = JSON.parse(response.body)
        expect(json['errors']['name']).to include('has already been taken')
      end
    end
  end

  describe 'PATCH #update' do
    let!(:category) { create(:category) }

    context 'with valid parameters' do
      let(:new_attributes) { { name: 'Updated Category' } }

      it 'updates the category' do
        patch :update, params: { id: category.to_param, category: new_attributes }
        category.reload
        expect(category.name).to eq('Updated Category')
      end

      it 'returns a success response' do
        patch :update, params: { id: category.to_param, category: new_attributes }
        expect(response).to be_successful
      end

      it 'returns the updated category' do
        patch :update, params: { id: category.to_param, category: new_attributes }
        json = JSON.parse(response.body)
        expect(json['category']['name']).to eq('Updated Category')
      end
    end

    context 'with invalid parameters' do
      it 'returns an unprocessable entity response' do
        patch :update, params: { id: category.to_param, category: invalid_attributes }
        expect(response).to have_http_status(:unprocessable_content)
      end

      it 'does not update the category' do
        original_name = category.name
        patch :update, params: { id: category.to_param, category: invalid_attributes }
        category.reload
        expect(category.name).to eq(original_name)
      end
    end

    context 'with non-existent category' do
      it 'returns 404' do
        patch :update, params: { id: 'nonexistent', category: valid_attributes }
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'DELETE #destroy' do
    context 'with category without transactions' do
      let!(:category) { create(:category) }

      it 'destroys the requested category' do
        expect {
          delete :destroy, params: { id: category.to_param }
        }.to change(Category, :count).by(-1)
      end

      it 'returns no content response' do
        delete :destroy, params: { id: category.to_param }
        expect(response).to have_http_status(:no_content)
      end
    end

    context 'with category that has transactions' do
      let!(:category) { create(:category) }
      let!(:transaction) { create(:transaction, category: category) }

      it 'destroys the category and associated transactions' do
        expect {
          delete :destroy, params: { id: category.to_param }
        }.to change(Category, :count).by(-1)
          .and change(Transaction, :count).by(-1)
      end
    end

    context 'with non-existent category' do
      it 'returns 404' do
        delete :destroy, params: { id: 'nonexistent' }
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'category statistics' do
    context 'with transactions in different categories' do
      let!(:groceries) { create(:category, :groceries) }
      let!(:transportation) { create(:category, :transportation) }

      before do
        create_list(:transaction, 3, category: groceries, amount: -50.0)
        create_list(:transaction, 2, category: transportation, amount: -30.0)
      end

      it 'includes correct transaction counts' do
        get :index
        json = JSON.parse(response.body)

        groceries_data = json['categories'].find { |c| c['name'] == 'Groceries' }
        transportation_data = json['categories'].find { |c| c['name'] == 'Transportation' }

        expect(groceries_data['transaction_count']).to eq(3)
        expect(transportation_data['transaction_count']).to eq(2)
      end
    end
  end

  describe 'JSON format' do
    let!(:category) { create(:category, name: 'Test Category', description: 'Test Description') }

    it 'returns properly formatted JSON' do
      get :show, params: { id: category.to_param }
      json = JSON.parse(response.body)

      expect(json).to have_key('category')
      expect(json['category']).to include('id', 'name', 'description', 'created_at', 'updated_at')
    end

    it 'includes timestamps in ISO format' do
      get :show, params: { id: category.to_param }
      json = JSON.parse(response.body)

      expect { DateTime.parse(json['category']['created_at']) }.not_to raise_error
      expect { DateTime.parse(json['category']['updated_at']) }.not_to raise_error
    end
  end
end
