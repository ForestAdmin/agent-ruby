class Account < ApplicationRecord
  belongs_to :supplier
  belongs_to :account_history
  has_one :order, through: :account_history
end
