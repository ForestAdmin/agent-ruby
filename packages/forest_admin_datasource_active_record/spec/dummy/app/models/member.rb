class Member < ApplicationRecord
  belongs_to :memberable, polymorphic: true
  belongs_to :user
end
