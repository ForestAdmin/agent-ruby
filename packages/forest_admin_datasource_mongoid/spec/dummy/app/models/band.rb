class Band
  include Mongoid::Document
  include Mongoid::Timestamps
  embeds_one :label
end
