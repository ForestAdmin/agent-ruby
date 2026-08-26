class Kid < ApplicationRecord
  belongs_to :owner, polymorphic: true
  has_one :detail, foreign_key: :custom_kid_id, inverse_of: :kid
end
