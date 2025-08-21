require 'rails_helper'

RSpec.describe 'Category Management', type: :system do
  before do
    driven_by(:selenium_chrome_headless)
  end

  let!(:category) { create(:category, name: 'Food & Dining', description: 'Restaurants and groceries', color: '#FF6B6B') }
  let!(:other_category) { create(:category, name: 'Transportation', description: 'Gas and public transport', color: '#4ECDC4') }
  let!(:transaction) { create(:transaction, category: category) }

  describe 'category statistics on dashboard' do
    before do
      visit root_path
      sleep(2) # Wait for React to load
    end

    it 'displays category count in stats', js: true do
      within('.stats-grid') do
        expect(page).to have_content('CATEGORIES')
        expect(page).to have_content('2')
      end
    end

    it 'shows categories in transaction listings', js: true do
      transactions_panel = page.all('.panel').find { |panel| panel.has_content?('Recent Transactions') }
      within(transactions_panel) do
        expect(page).to have_content(category.name)
      end
    end

    it 'displays uncategorized label for transactions without category', js: true do
      create(:transaction, category: nil, description: 'Uncategorized Transaction')

      visit root_path
      sleep(2)

      transactions_panel = page.all('.panel').find { |panel| panel.has_content?('Recent Transactions') }
      within(transactions_panel) do
        expect(page).to have_content('Uncategorized')
      end
    end
  end

  describe 'category API endpoints' do
    it 'provides link to view all categories via API', js: true do
      visit root_path
      sleep(2)

      expect(page).to have_link('View Categories', href: '/api/v1/categories')
    end
  end
end
