class Detail < ApplicationRecord
  belongs_to :kid, foreign_key: :custom_kid_id, inverse_of: :detail
end
