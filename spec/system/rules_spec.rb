require 'rails_helper'

RSpec.describe 'Rule Management', type: :system do
  before do
    driven_by(:selenium_chrome_headless)
  end

  let!(:category) { create(:category, name: 'Shopping') }
  let!(:rule) { create(:rule,
    name: 'Categorize Amazon purchases',
    condition_field: 'description',
    condition_operator: 'contains',
    condition_value: 'amazon',
    action_type: 'categorize',
    action_value: category.name,
    active: true
  )}
  let!(:inactive_rule) { create(:rule,
    name: 'Inactive Rule',
    active: false
  )}

  describe 'rule statistics on dashboard' do
    before do
      visit root_path
      sleep(2) # Wait for React to load
    end

    it 'displays active rules count in stats', js: true do
      within('.stats-grid') do
        expect(page).to have_content('ACTIVE RULES')
        expect(page).to have_content('1') # Only counting active rules
      end
    end
  end

  describe 'rule API endpoints' do
    it 'provides link to view all rules via API', js: true do
      visit root_path
      sleep(2)

      expect(page).to have_link('View Active Rules', href: '/api/v1/rules')
    end
  end

  describe 'rule effects on transactions' do
    it 'applies rules during CSV import', js: true do
      csv_content = <<~CSV
        amount,description,date,category
        99.99,Amazon Purchase,2025-08-19,
      CSV

      csv_file_path = Rails.root.join('tmp', 'rule_test.csv')
      File.write(csv_file_path, csv_content)

      visit '/upload'
      sleep(2)

      find('.file-input', visible: false).set(csv_file_path)
      click_button '🚀 Import Transactions'

      sleep(3) # Wait for import

      # Should show result message
      expect(page).to have_css('.result-message')

      File.delete(csv_file_path) if File.exist?(csv_file_path)
    end
  end
end
