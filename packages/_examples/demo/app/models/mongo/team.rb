module Mongo
  class Team
    include Mongoid::Document
    include Mongoid::Timestamps
    field :label, type: String

    has_one :user, as: :item, class_name: 'Mongo::User'
  end
end
