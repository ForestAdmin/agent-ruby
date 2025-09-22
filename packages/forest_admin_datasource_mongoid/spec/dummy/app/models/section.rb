class Section
  include Mongoid::Document
  field :content, type: String
  field :body, type: String
  embedded_in :label
end
