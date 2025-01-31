class Post
  include Mongoid::Document
  include Mongoid::Timestamps
  field :title, type: String
  field :body, type: String
  field :rating, type: Integer

  has_many :comments, dependent: :destroy
  has_one :author
  has_and_belongs_to_many :tags
end
