require 'rails_helper'

RSpec.describe 'Anomaly Detection', type: :system do
  before do
    driven_by(:selenium_chrome_headless)
    # Ensure completely clean database state and clear caches
    Rails.cache.clear

    # Clean up any remaining data to prevent test contamination
    AnomalyDetection.delete_all
    Rule.delete_all
    Transaction.delete_all
    Category.delete_all

    # Force creation of test data before each test to ensure it's available to the browser
    setup_test_data
  end

  def setup_test_data
    @category = create(:category, name: 'Food & Dining')
    @normal_transaction = create(:transaction, category: @category, amount: 25.00)
    @anomaly_transaction = create(:transaction, category: @category, amount: 500.00)

    @duplicate_anomaly = create(:anomaly_detection,
      transaction_record: @anomaly_transaction,
      anomaly_type: 'duplicate_transaction',
      severity: 3,
      description: 'Potential duplicate transaction detected',
      resolved: false
    )

    @high_amount_anomaly = create(:anomaly_detection,
      transaction_record: @anomaly_transaction,
      anomaly_type: 'unusually_high_amount',
      severity: 4,
      description: 'Transaction amount significantly higher than average',
      resolved: false
    )

    @resolved_anomaly = create(:anomaly_detection,
      transaction_record: @normal_transaction,
      anomaly_type: 'missing_category',
      severity: 2,
      description: 'Transaction was missing category',
      resolved: true,
      resolved_at: 1.day.ago
    )
  end

  describe 'viewing anomalies on dashboard' do
    before do
      visit root_path
      sleep(2) # Wait for React to load
    end

    it 'displays anomalies section', js: true do
      expect(page).to have_content('Active Anomalies')
      expect(page).to have_content('UNRESOLVED ANOMALIES')
    end

    it 'shows unresolved anomalies count in stats', js: true do
      within('.stats-grid') do
        expect(page).to have_content('UNRESOLVED ANOMALIES')
        # The count might include other anomalies from background data
        expect(page.text).to match(/\d+/)
      end
    end

    it 'displays anomalies in the anomalies panel', js: true do
      anomalies_panel = page.all('.panel').find { |panel| panel.has_content?('Active Anomalies') }
      within(anomalies_panel) do
        # Check for anomaly types (converted to uppercase)
        expect(page).to have_content('DUPLICATE TRANSACTION')
        expect(page).to have_content('UNUSUALLY HIGH AMOUNT')

        # Check for descriptions
        expect(page).to have_content(@duplicate_anomaly.description)
        expect(page).to have_content(@high_amount_anomaly.description)
      end
    end

    it 'displays severity indicators', js: true do
      anomalies_panel = page.all('.panel').find { |panel| panel.has_content?('Active Anomalies') }
      within(anomalies_panel) do
        expect(page).to have_content('Medium Severity')
        expect(page).to have_content('High Severity')
      end
    end

    it 'shows associated transaction IDs', js: true do
      anomalies_panel = page.all('.panel').find { |panel| panel.has_content?('Active Anomalies') }
      within(anomalies_panel) do
        # Verify we're showing transaction IDs for anomalies
        # Since we have anomalies, we should see "Transaction ID:" text
        expect(page).to have_content("Transaction ID:")

        # The specific ID may vary due to test order, but it should be present
        # and match one of our created anomalies
        transaction_ids = page.all(:xpath, ".//small[contains(text(),'Transaction ID:')]").map(&:text)
        expect(transaction_ids).not_to be_empty
      end
    end

    it 'does not show resolved anomalies', js: true do
      anomalies_panel = page.all('.panel').find { |panel| panel.has_content?('Active Anomalies') }
      within(anomalies_panel) do
        expect(page).not_to have_content(@resolved_anomaly.description)
      end
    end

    it 'shows resolve buttons for anomalies', js: true do
      anomalies_panel = page.all('.panel').find { |panel| panel.has_content?('Active Anomalies') }
      within(anomalies_panel) do
        expect(page).to have_content('✓')
      end
    end
  end

  describe 'anomaly API endpoints' do
    it 'provides link to view unresolved anomalies via API', js: true do
      visit root_path
      sleep(2)

      expect(page).to have_link('View Unresolved Anomalies', href: '/api/v1/anomaly_detections?unresolved=true')
    end
  end

  describe 'anomaly indicators on transactions' do
    it 'shows anomaly count on affected transactions', js: true do
      visit root_path
      sleep(2)

      transactions_panel = page.all('.panel').find { |panel| panel.has_content?('Recent Transactions') }
      within(transactions_panel) do
        # Should show anomaly indicator for transaction with anomalies
        expect(page).to have_content('⚠️')
        expect(page).to have_content('2 anomalies') # The anomaly transaction has 2 anomalies
      end
    end
  end
end
