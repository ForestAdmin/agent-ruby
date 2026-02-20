class User < ApplicationRecord
  has_one :document, as: :documentable
end
