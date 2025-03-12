module Mongo
  class Tag
    include Mongoid::Document
    include Mongoid::Timestamps
    field :label, type: String

    has_and_belongs_to_many :posts, class_name: 'Mongo::Post'
  end
end
