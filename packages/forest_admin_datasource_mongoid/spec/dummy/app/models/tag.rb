class Tag
  include Mongoid::Document
  include Mongoid::Timestamps
  field :label, type: String

  has_and_belongs_to_many :posts
end
