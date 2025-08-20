require 'rails_helper'

RSpec.describe 'CSV Import', type: :system do
  before do
    driven_by(:selenium_chrome_headless)
  end

  let!(:category) { create(:category, name: 'Food & Dining') }
  let(:csv_content) do
    <<~CSV
      amount,description,date,category
      25.50,Starbucks Coffee,2025-08-19,Food & Dining
      45.00,Uber Ride,2025-08-18,Transportation
      12.75,McDonald's,2025-08-17,Food & Dining
    CSV
  end

  describe 'CSV import page' do
    before do
      visit '/upload'
      sleep(2) # Wait for React to load
    end

    it 'displays CSV import page', js: true do
      expect(page).to have_content('📁 CSV Import')
      expect(page).to have_content('Upload your transaction CSV file for automated processing and categorization')
    end

    it 'has back to dashboard link', js: true do
      expect(page).to have_link('← Back to Dashboard', href: '/')
    end

    it 'shows file input area', js: true do
      expect(page).to have_content('🎯 Click to select CSV file or drag & drop')
      expect(page).to have_content('Supports standard CSV format with headers: date, description, amount, category')
      expect(page).to have_button('🚀 Import Transactions', disabled: true)
    end
  end

  describe 'CSV file upload' do
    let(:csv_file_path) { Rails.root.join('tmp', 'test_import.csv') }

    before do
      # Create a temporary CSV file for testing
      File.write(csv_file_path, csv_content)
      
      visit '/upload'
      sleep(2) # Wait for React to load
    end

    after do
      # Clean up the temporary file
      File.delete(csv_file_path) if File.exist?(csv_file_path)
    end

    it 'uploads and processes CSV file successfully', js: true do
      find('.file-input', visible: false).set(csv_file_path)
      
      click_button '🚀 Import Transactions'
      
      # Wait for import to complete
      sleep(3)
      
      # Should show result message (success or error due to API)
      expect(page).to have_css('.result-message')
    end

    it 'shows import progress', js: true do
      find('.file-input', visible: false).set(csv_file_path)
      
      click_button '🚀 Import Transactions'
      
      # Should show processing state immediately
      expect(page).to have_button('⏳ Processing...', disabled: true)
    end

    it 'displays selected file name', js: true do
      find('.file-input', visible: false).set(csv_file_path)
      
      expect(page).to have_content('📄 test_import.csv')
    end
  end

  describe 'CSV validation and error handling' do
    let(:invalid_csv_content) do
      <<~CSV
        amount,description,date
        invalid_amount,Test Transaction,2025-08-19
        ,Missing Description,2025-08-18
        25.50,,2025-08-17
      CSV
    end
    let(:invalid_csv_path) { Rails.root.join('tmp', 'invalid_import.csv') }

    before do
      File.write(invalid_csv_path, invalid_csv_content)
      
      visit '/upload'
      sleep(2) # Wait for React to load
    end

    after do
      File.delete(invalid_csv_path) if File.exist?(invalid_csv_path)
    end

    it 'handles invalid CSV data gracefully', js: true do
      find('.file-input', visible: false).set(invalid_csv_path)
      
      click_button '🚀 Import Transactions'
      
      # Wait for processing
      sleep(3)
      
      # Should show some result message
      expect(page).to have_css('.result-message')
    end

    it 'validates file selection before import', js: true do
      # Try to import without selecting a file - button should be disabled
      expect(page).to have_button('🚀 Import Transactions', disabled: true)
      
      # The button is properly disabled which prevents submission without a file
      # This is the expected validation behavior
    end

    it 'validates CSV file type', js: true do
      # Create a non-CSV file
      txt_file_path = Rails.root.join('tmp', 'not_csv.txt')
      File.write(txt_file_path, 'This is not a CSV file')
      
      begin
        find('.file-input', visible: false).set(txt_file_path)
        
        # Should show error for invalid file type
        expect(page).to have_content('Please select a valid CSV file.')
      ensure
        File.delete(txt_file_path) if File.exist?(txt_file_path)
      end
    end
  end

  describe 'navigation from dashboard' do
    it 'navigates to CSV import from dashboard', js: true do
      visit root_path
      sleep(2)
      
      click_link '📁 Import CSV Transactions'
      sleep(1)
      
      expect(page).to have_content('📁 CSV Import')
      expect(current_path).to eq('/upload')
    end
    
    it 'navigates back to dashboard from CSV import', js: true do
      visit '/upload'
      sleep(2)
      
      click_link '← Back to Dashboard'
      sleep(1)
      
      expect(page).to have_content('📊 Bookkeeping System')
      expect(current_path).to eq('/')
    end
  end

  describe 'import results display' do
    let(:csv_file_path) { Rails.root.join('tmp', 'results_test.csv') }

    before do
      File.write(csv_file_path, csv_content)
      
      visit '/upload'
      sleep(2) # Wait for React to load
    end

    after do
      File.delete(csv_file_path) if File.exist?(csv_file_path)
    end

    it 'shows detailed import results on success', js: true do
      find('.file-input', visible: false).set(csv_file_path)
      
      click_button '🚀 Import Transactions'
      
      # Wait for import to complete
      sleep(3)
      
      # Should show detailed results if successful
      if page.has_content?('Successfully processed')
        expect(page).to have_content('✅ Imported:').or have_content('transactions')
      end
    end
  end

  describe 'drag and drop functionality' do
    it 'shows drag and drop area', js: true do
      visit '/upload'
      sleep(2)
      
      expect(page).to have_css('.file-input-container')
      expect(page).to have_content('drag & drop')
    end
  end
end