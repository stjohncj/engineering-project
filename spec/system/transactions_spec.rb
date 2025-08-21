require 'rails_helper'

RSpec.describe 'Transaction Management', type: :system do
  before do
    driven_by(:selenium_chrome_headless)
  end

  let!(:category) { create(:category, name: 'Food & Dining') }
  let!(:other_category) { create(:category, name: 'Transportation') }
  let!(:transaction) { create(:transaction, category: category, description: 'Test Transaction', amount: 50.00) }

  describe 'viewing transactions on dashboard' do
    before do
      visit root_path
      sleep(2) # Wait for React to load
    end

    it 'displays transactions in the Recent Transactions section', js: true do
      expect(page).to have_content('Recent Transactions')

      # Find the transactions panel
      transactions_panel = page.all('.panel').find { |panel| panel.has_content?('Recent Transactions') }
      within(transactions_panel) do
        expect(page).to have_content(transaction.description)
        expect(page).to have_content("$#{'%.2f' % transaction.amount}")
        expect(page).to have_content(category.name)
      end
    end

    it 'shows transaction date', js: true do
      transactions_panel = page.all('.panel').find { |panel| panel.has_content?('Recent Transactions') }
      within(transactions_panel) do
        # Date format might be different based on locale settings
        expect(page.text).to match(/\w{3} \d{1,2}, \d{4}/) # Matches format like "Aug 19, 2025"
      end
    end

    it 'displays transaction status', js: true do
      transactions_panel = page.all('.panel').find { |panel| panel.has_content?('Recent Transactions') }
      within(transactions_panel) do
        expect(page).to have_content(transaction.status.upcase)
      end
    end

    it 'shows anomaly indicators for flagged transactions', js: true do
      # Create an anomaly for the transaction
      create(:anomaly_detection, transaction_record: transaction)

      visit root_path
      sleep(2)

      transactions_panel = page.all('.panel').find { |panel| panel.has_content?('Recent Transactions') }
      within(transactions_panel) do
        expect(page).to have_content('⚠️')
        expect(page).to have_content('anomaly')
      end
    end
  end

  describe 'transaction API endpoints' do
    it 'provides link to view all transactions via API', js: true do
      visit root_path
      sleep(2)

      expect(page).to have_link('View All Transactions', href: '/api/v1/transactions')
    end
  end

  describe 'transaction count in stats' do
    before do
      create_list(:transaction, 4, category: category)
      visit root_path
      sleep(2)
    end

    it 'shows correct total transaction count', js: true do
      within('.stats-grid') do
        expect(page).to have_content('TOTAL TRANSACTIONS')
        expect(page).to have_content('5') # 1 original + 4 new
      end
    end
  end
end
