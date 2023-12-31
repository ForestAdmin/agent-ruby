RSpec.shared_context 'with caller' do
  let(:caller) do
    ForestAdminDatasourceToolkit::Components::Caller.new(
      id: 1,
      email: 'sarah.connor@skynet.com',
      first_name: 'sarah',
      last_name: 'connor',
      team: 'survivor',
      rendering_id: 1,
      tags: [],
      timezone: 'Europe/Paris',
      permission_level: 'admin',
      role: 'dev'
    )
  end
end
