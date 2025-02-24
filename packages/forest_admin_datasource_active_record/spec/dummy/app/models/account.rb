class Account < ApplicationRecord
  belongs_to :supplier
  belongs_to :account_history
end
