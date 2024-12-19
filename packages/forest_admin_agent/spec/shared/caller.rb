RSpec.shared_context 'with caller' do
  let(:bearer) do
    'Bearer eyJhbGciOiJIUzI1NiJ9.eyJpZCI6IjEiLCJlbWFpbCI6Im5pY29sYXNhQGZvcmVzdGFkbWluLmNvbSIsImZpcnN0X25hbWUiOiJOaWNvbGFzIiwibGFzdF9uYW1lIjoiQWxleGFuZHJlIiwidGVhbSI6Ik9wZXJhdGlvbnMiLCJ0YWdzIjpbXSwicmVuZGVyaW5nX2lkIjoxMTQsImV4cCI6MTk5ODAzNjQ0OSwicGVybWlzc2lvbl9sZXZlbCI6ImFkbWluIn0.5LFmtMqZMfinLZLGdPvTlr22YDfU-B30z7MQxlb8vng'
  end

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
      role: 'dev',
      request: { ip: '127.0.0.1' }
    )
  end
end
