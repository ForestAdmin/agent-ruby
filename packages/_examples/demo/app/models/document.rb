class Document < ApplicationRecord
  belongs_to :documentable, polymorphic: true
end
