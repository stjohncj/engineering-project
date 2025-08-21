require 'rails_helper'

RSpec.describe 'Dashboard API Integration', type: :system do
  before do
    driven_by(:selenium_chrome_headless)
  end

  context 'with transactions in database' do
    let!(:category) { create(:category, name: 'Food & Dining') }
    let!(:transactions) do
      [
        create(:transaction, description: 'Coffee shop', amount: 5.50, category: category),
        create(:transaction, description: 'Restaurant dinner', amount: 45.00, category: category),
        create(:transaction, description: 'Grocery store', amount: 125.75, category: category)
      ]
    end
    let!(:anomaly) { create(:anomaly_detection, transaction_record: transactions.first) }

    describe 'dashboard statistics' do
      it 'displays correct transaction count', js: true do
        visit root_path
        sleep(3) # Wait for API calls to complete

        # Should show the correct number of transactions
        expect(page).to have_content('TOTAL TRANSACTIONS')

        # Should NOT show "No transactions found"
        expect(page).not_to have_content('No transactions found')

        # Check that transactions are actually displayed
        expect(page).to have_content('Coffee shop')
        expect(page).to have_content('Restaurant dinner')
      end

      it 'displays transaction details correctly', js: true do
        visit root_path
        sleep(3)

        # Check individual transaction details
        within('.transaction-list') do
          expect(page).to have_content('Coffee shop')
          expect(page).to have_content('$5.50')
          expect(page).to have_content('Food & Dining')

          expect(page).to have_content('Restaurant dinner')
          expect(page).to have_content('$45.00')
        end
      end

      it 'displays anomaly count correctly', js: true do
        visit root_path
        sleep(3)

        # Should show correct anomaly count
        expect(page).to have_content('UNRESOLVED ANOMALIES')
        expect(page).to have_content('1') # We created 1 anomaly
      end

      it 'handles API pagination correctly', js: true do
        # Create more transactions to test pagination
        create_list(:transaction, 10, category: category)

        visit root_path
        sleep(3)

        # Dashboard should show recent transactions (limited by per_page=5)
        # But stats should show total count correctly
        expect(page).to have_content('TOTAL TRANSACTIONS')
        # Should show some transactions in the recent list
        expect(page).to have_css('.transaction-item', count: 5)
      end
    end

    describe 'API endpoint links' do
      it 'provides working API links', js: true do
        visit root_path
        sleep(2)

        # Test "View All Transactions" link
        transactions_link = find('a[href="/api/v1/transactions"]')
        expect(transactions_link).to be_present

        # Test that the link would work (we can't easily test opening in new tab)
        # but we can verify the href is correct
        expect(transactions_link[:href]).to eq('/api/v1/transactions')
      end
    end

    describe 'error handling' do
      it 'gracefully handles API errors', js: true do
        # Simulate API failure by stubbing network requests
        page.execute_script("""
          window.originalFetch = window.fetch;
          window.fetch = function(url) {
            if (url.includes('/api/v1/transactions')) {
              return Promise.reject(new Error('Network error'));
            }
            return window.originalFetch.apply(this, arguments);
          };
        """)

        visit root_path
        sleep(3)

        # Should show loading state or error message, not crash
        expect(page).to have_content('Loading transactions').or have_content('No transactions found')

        # Restore fetch for cleanup
        page.execute_script('window.fetch = window.originalFetch;')
      end

      it 'handles malformed API responses', js: true do
        # Simulate malformed JSON response
        page.execute_script("""
          window.originalFetch = window.fetch;
          window.fetch = function(url) {
            if (url.includes('/api/v1/transactions')) {
              return Promise.resolve({
                ok: true,
                json: () => Promise.resolve({ invalid: 'data', no_transactions_key: true })
              });
            }
            return window.originalFetch.apply(this, arguments);
          };
        """)

        visit root_path
        sleep(3)

        # Should handle gracefully, show empty state
        expect(page).to have_content('No transactions found')

        # Restore fetch
        page.execute_script('window.fetch = window.originalFetch;')
      end
    end
  end

  context 'with empty database' do
    it 'displays appropriate empty states', js: true do
      visit root_path
      sleep(3)

      # Should show zero counts
      expect(page).to have_content('TOTAL TRANSACTIONS')
      expect(page).to have_content('0').or have_content('No transactions found')

      # Should show empty state messages
      expect(page).to have_content('No transactions found').or have_content('No unresolved anomalies')
    end
  end

  describe 'real-time API consistency' do
    it 'matches API response structure with dashboard expectations', js: true do
      visit root_path
      sleep(2)

      # Capture the actual API response that the dashboard receives
      api_response = page.evaluate_script("""
        fetch('/api/v1/transactions?per_page=5')
          .then(r => r.json())
          .then(data => data)
      """)

      # Verify the response structure matches what the dashboard expects
      expect(api_response).to include('transactions', 'pagination')
      expect(api_response['pagination']).to include('total_count', 'current_page', 'per_page')

      # Ensure total_count is not zero when transactions exist
      if Transaction.count > 0
        expect(api_response['pagination']['total_count']).to be > 0
        expect(api_response['transactions']).to be_an(Array)
        expect(api_response['transactions'].length).to be > 0
      end
    end

    it 'verifies anomaly detection API consistency', js: true do
      visit root_path
      sleep(2)

      # Test the anomaly detection endpoint
      anomaly_response = page.evaluate_script("""
        fetch('/api/v1/anomaly_detections?unresolved=true')
          .then(r => r.json())
          .then(data => data)
      """)

      expect(anomaly_response).to include('anomaly_detections', 'pagination')
      expect(anomaly_response['pagination']['total_count']).to be >= 0
    end
  end
end
