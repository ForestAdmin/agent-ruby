class Solo < ApplicationRecord
  has_one :kid, as: :owner
  has_one :detail, through: :kid
end
