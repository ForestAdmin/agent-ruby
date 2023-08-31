require_relative '../lib/forestadmin_agent'

RSpec.describe ForestadminAgent do
  it "has a version number" do
    expect(ForestadminAgent::VERSION).not_to eq 1
  end
  # pending "should something"
end
