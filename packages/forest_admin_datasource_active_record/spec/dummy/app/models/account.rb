class Account < ApplicationRecord
  belongs_to :supplier
  belongs_to :account_history
  has_one :order, through: :account_history
  belongs_to :secondary_history, class_name: 'AccountHistory', optional: true
  belongs_to :note, class_name: 'Api::Note', optional: true
end
