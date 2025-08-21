class Category < ApplicationRecord
  has_many :transactions, dependent: :destroy

  validates :name, presence: true, uniqueness: { case_sensitive: false }
  validates :color, format: { with: /\A#[0-9A-Fa-f]{6}\z/, message: "must be a valid hex color" }, allow_blank: true

  scope :with_transactions, -> { joins(:transactions).distinct }

  def transaction_count
    transactions.count
  end

  def total_amount
    transactions.sum(:amount)
  end

  def to_s
    name
  end
end
