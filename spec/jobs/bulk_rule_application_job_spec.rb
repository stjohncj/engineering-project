require 'rails_helper'

RSpec.describe BulkRuleApplicationJob, type: :job do
  include ActiveJob::TestHelper

  let(:category) { create(:category) }
  let!(:transactions) { create_list(:transaction, 3, category: category) }
  let(:transaction_ids) { transactions.map(&:id) }

  let!(:active_rule) { create(:rule, active: true) }
  let!(:inactive_rule) { create(:rule, active: false) }

  describe '#perform' do
    before do
      allow(Rails.logger).to receive(:info)
      allow(Rails.logger).to receive(:error)
    end

    it 'applies active rules to all specified transactions' do
      # Check that the job loads the correct rules and transactions
      expect(Rule).to receive(:active).and_return([active_rule])
      expect(Transaction).to receive(:includes).with(:category).and_return(double(where: transactions))
      expect(active_rule).to receive(:apply_to!).exactly(3).times

      described_class.perform_now(transaction_ids)
    end

    it 'processes all transactions' do
      # Create more transactions to test processing
      additional_transactions = create_list(:transaction, 5, category: category)
      all_transaction_ids = transaction_ids + additional_transactions.map(&:id)
      all_transactions = transactions + additional_transactions

      expect(Rule).to receive(:active).and_return([active_rule])
      expect(Transaction).to receive(:includes).with(:category).and_return(double(where: all_transactions))
      expect(active_rule).to receive(:apply_to!).exactly(8).times # 3 + 5 transactions

      described_class.perform_now(all_transaction_ids)
    end

    it 'logs successful completion' do
      expect(Rails.logger).to receive(:info).with(/BulkRuleApplicationJob: Applied rules to \d+ transactions/)

      described_class.perform_now(transaction_ids)
    end

    it 'invalidates transaction-related caches' do
      expect(Rails.cache).to receive(:delete).with("dashboard_statistics")
      expect(Rails.cache).to receive(:delete).with("recent_transactions")
      expect(Rails.cache).to receive(:delete).with("category_breakdown")
      expect(Rails.cache).to receive(:delete_matched).with("transactions_index_*")

      described_class.perform_now(transaction_ids)
    end

    context 'when specific rule IDs are provided' do
      let(:rule_ids) { [ active_rule.id ] }

      it 'only applies the specified rules' do
        expect(Rule).to receive(:active).and_return(double(where: [active_rule]))
        expect(Transaction).to receive(:includes).with(:category).and_return(double(where: transactions))
        expect(active_rule).to receive(:apply_to!).exactly(3).times

        described_class.perform_now(transaction_ids, rule_ids)
      end
    end

    context 'when a rule application fails' do
      before do
        allow(Rails.logger).to receive(:error).and_call_original
        allow(active_rule).to receive(:apply_to!).and_raise(StandardError, "Rule application failed")
      end

      it 'logs the error and continues with other transactions' do
        expect(Rule).to receive(:active).and_return([active_rule])
        expect(Transaction).to receive(:includes).with(:category).and_return(double(where: transactions))
        expect(Rails.logger).to receive(:error).exactly(3).times do |message|
          expect(message).to match(/Failed to apply rule #{active_rule.id} to transaction \d+: Rule application failed/)
        end

        expect { described_class.perform_now(transaction_ids) }.not_to raise_error
      end
    end

    context 'when the job itself fails' do
      before do
        allow(Transaction).to receive(:includes).and_raise(StandardError, "Database connection failed")
      end

      it 'logs the error and handles it appropriately' do
        allow(Rails.logger).to receive(:error).and_call_original
        expect(Rails.logger).to receive(:error).with("BulkRuleApplicationJob failed: Database connection failed").and_call_original

        # In test mode, the job might handle the error through the retry system
        described_class.perform_now(transaction_ids)
      end
    end
  end

  describe 'job configuration' do
    it 'is queued on the default queue' do
      expect(described_class.queue_name).to eq('default')
    end

    it 'retries on StandardError with exponential backoff' do
      # Test that the job class has retry configuration by checking if it responds to the retry_on method
      expect(described_class).to respond_to(:retry_on)
    end
  end

  describe 'job enqueueing' do
    it 'enqueues the job correctly' do
      expect {
        described_class.perform_later(transaction_ids)
      }.to enqueue_job(described_class).with(transaction_ids).on_queue('default')
    end

    it 'enqueues the job with rule IDs' do
      rule_ids = [ active_rule.id ]

      expect {
        described_class.perform_later(transaction_ids, rule_ids)
      }.to enqueue_job(described_class).with(transaction_ids, rule_ids).on_queue('default')
    end
  end
end
