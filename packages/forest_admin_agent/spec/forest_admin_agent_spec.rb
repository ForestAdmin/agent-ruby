require_relative '../lib/forest_admin_agent'

RSpec.describe ForestAdminAgent do
  it "has a version number" do
    expect(ForestAdminAgent::VERSION).not_to eq 1
  end
  # pending "should something"
end
