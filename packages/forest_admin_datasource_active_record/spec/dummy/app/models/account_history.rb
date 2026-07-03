class AccountHistory < ApplicationRecord
  has_one :account
  belongs_to :order, optional: true
end
