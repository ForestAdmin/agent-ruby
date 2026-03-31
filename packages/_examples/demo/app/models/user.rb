class User < ApplicationRecord
  has_one :document, as: :documentable
  has_one_attached :avatar
end
