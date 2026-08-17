module ForestAdminDatasourcePylon
  # Observed through PylonIssue, the only collection carrying a conversation.
  RSpec.describe Collections::Issue::MessagesEmbedder do
    def filter(condition_tree: nil, search: nil, page: nil)
      ForestAdminDatasourceToolkit::Components::Query::Filter.new(
        condition_tree: condition_tree, search: search, page: page
      )
    end

    def json(payload, status = 200)
      { status: status, body: payload.to_json, headers: { 'Content-Type' => 'application/json' } }
    end

    def issue_payload(id, overrides = {})
      { 'id' => id, 'title' => 'Boom' }.merge(overrides)
    end

    # Trimmed to the shape observed on the API: the author carries a contact or
    # a user side, and unset values come back as null rather than absent.
    def message_payload(id, overrides = {})
      {
        'id' => id, 'message_html' => '<p>hello</p>', 'is_private' => false, 'source' => 'email',
        'thread_id' => nil, 'file_urls' => [], 'timestamp' => '2026-08-07T13:06:22Z',
        'author' => { 'name' => 'Ada', 'avatar_url' => 'https://cdn/ada.png',
                      'contact' => { 'id' => 'con-1', 'email' => 'ada@acme.com' }, 'user' => nil }
      }.merge(overrides)
    end

    def stub_issues(*payloads)
      stub_request(:post, "#{base}/issues/search").to_return(json('data' => payloads))
    end

    def stub_messages(issue_id, *payloads)
      stub_request(:get, "#{base}/issues/#{issue_id}/messages").to_return(json('data' => payloads))
    end

    let(:datasource) { ForestAdminDatasourcePylon::Datasource.new(api_key: 'k') }
    let(:issues) { datasource.get_collection('PylonIssue') }
    let(:base) { datasource.configuration.url }
    let(:logger) { instance_double(Logger, warn: nil) }

    before { stub_custom_fields }

    describe 'the schema of the column' do
      it 'declares messages as an array of message shapes' do
        expect(issues.fields['messages'].column_type).to eq([Collections::Issue::MESSAGE_THREAD_SCHEMA])
      end

      it 'names the fields after the columns of the collection, not after the payload' do
        expect(Collections::Issue::MESSAGE_THREAD_SCHEMA.keys).to include('body_html', 'created_at')
        expect(Collections::Issue::MESSAGE_THREAD_SCHEMA.keys).not_to include('message_html', 'timestamp')
      end

      it 'advertises no filter and no sort on a thread the search endpoint does not cover' do
        expect(issues.fields['messages'].filter_operators).to eq([])
        expect(issues.fields['messages'].is_sortable).to be(false)
      end

      it 'is read-only, like every other column of this story' do
        expect(issues.fields['messages'].is_read_only).to be(true)
      end
    end

    describe 'what the projection asks for' do
      before { stub_issues(issue_payload('i1')) }

      it 'reads the thread when the projection names it' do
        stub_messages('i1', message_payload('msg-1'))

        rows = issues.list(nil, filter, %w[id messages])

        expect(rows.first['messages'].map { |m| m['id'] }).to eq(%w[msg-1])
        expect(WebMock).to have_requested(:get, "#{base}/issues/i1/messages").once
      end

      it 'reads the thread when the projection reaches inside it' do
        stub_messages('i1', message_payload('msg-1'))

        expect(issues.list(nil, filter, %w[id messages:body_html]).first['messages']).not_to be_nil
      end

      it 'reads no thread when the projection does not name it' do
        rows = issues.list(nil, filter, %w[id title])

        expect(rows.first).not_to have_key('messages')
        expect(WebMock).not_to have_requested(:get, "#{base}/issues/i1/messages")
      end

      # A count and an export both go through a nil projection: neither asked
      # for the conversation, and both would pay one request per row for it.
      it 'reads no thread when the projection is nil' do
        expect(issues.list(nil, filter, nil).first).not_to have_key('messages')
        expect(WebMock).not_to have_requested(:get, "#{base}/issues/i1/messages")
      end
    end

    describe 'the shape of an embedded message' do
      before { stub_issues(issue_payload('i1')) }

      it 'renames message_html and timestamp after the columns of the collection' do
        stub_messages('i1', message_payload('msg-1'))

        message = issues.list(nil, filter, %w[id messages]).first['messages'].first

        expect(message).to include('id' => 'msg-1', 'body_html' => '<p>hello</p>', 'is_private' => false,
                                   'source' => 'email', 'created_at' => '2026-08-07T13:06:22Z')
      end

      it 'fills every field the column schema declares' do
        stub_messages('i1', message_payload('msg-1'))

        message = issues.list(nil, filter, %w[id messages]).first['messages'].first

        expect(message.keys).to match_array(Collections::Issue::MESSAGE_THREAD_SCHEMA.keys)
      end

      it 'keeps the thread in the order Pylon returns it, oldest first' do
        stub_messages('i1', message_payload('msg-1'), message_payload('msg-2'), message_payload('msg-3'))

        rows = issues.list(nil, filter, %w[id messages])

        expect(rows.first['messages'].map { |m| m['id'] }).to eq(%w[msg-1 msg-2 msg-3])
      end

      it 'embeds an empty thread as an empty list' do
        stub_messages('i1')

        expect(issues.list(nil, filter, %w[id messages]).first['messages']).to eq([])
      end
    end

    describe 'the author of a message' do
      before { stub_issues(issue_payload('i1')) }

      def author_of(payload)
        stub_messages('i1', payload)
        issues.list(nil, filter, %w[id messages]).first['messages'].first
      end

      it 'flattens the contact side of a message written by a customer' do
        expect(author_of(message_payload('msg-1'))).to include(
          'author_name' => 'Ada', 'author_avatar_url' => 'https://cdn/ada.png',
          'author_email' => 'ada@acme.com', 'author_contact_id' => 'con-1', 'author_user_id' => nil
        )
      end

      it 'flattens the user side of a message written by an agent' do
        author = { 'name' => 'Grace', 'avatar_url' => nil, 'contact' => nil,
                   'user' => { 'id' => 'usr-1', 'email' => 'grace@support.io' } }

        expect(author_of(message_payload('msg-1', 'author' => author))).to include(
          'author_name' => 'Grace', 'author_email' => 'grace@support.io',
          'author_contact_id' => nil, 'author_user_id' => 'usr-1'
        )
      end

      # Pylon puts both sides side by side with nothing telling them apart; the
      # contact is the one the customer-facing thread is about.
      it 'prefers the contact email when both sides are there' do
        author = { 'name' => 'Ada', 'contact' => { 'id' => 'con-1', 'email' => 'ada@acme.com' },
                   'user' => { 'id' => 'usr-1', 'email' => 'ada@support.io' } }

        expect(author_of(message_payload('msg-1', 'author' => author))).to include(
          'author_email' => 'ada@acme.com', 'author_contact_id' => 'con-1', 'author_user_id' => 'usr-1'
        )
      end

      it 'leaves every author field null when the message carries no author' do
        expect(author_of(message_payload('msg-1', 'author' => nil))).to include(
          'author_name' => nil, 'author_email' => nil, 'author_avatar_url' => nil,
          'author_contact_id' => nil, 'author_user_id' => nil
        )
      end
    end

    describe 'the fan-out it allows' do
      let(:cap) { Collections::Issue::MAX_MESSAGE_EMBEDS }

      before do
        stub_issues(*(1..(cap + 2)).map { |i| issue_payload("i#{i}") })
        (1..(cap + 2)).each { |i| stub_messages("i#{i}", message_payload("msg-#{i}")) }
      end

      it 'reads one thread per row up to the cap' do
        issues.list(nil, filter, %w[id messages])

        expect(WebMock).to have_requested(:get, "#{base}/issues/i#{cap}/messages").once
        expect(WebMock).not_to have_requested(:get, "#{base}/issues/i#{cap + 1}/messages")
      end

      # Never the empty list: "no thread read" is not "this issue has no
      # message", and the operator has to be able to tell them apart.
      it 'leaves the rows past the cap at nil rather than at an empty thread' do
        rows = issues.list(nil, filter, %w[id messages])

        expect(rows.first(cap).map { |row| row['messages'] }).to all(be_an(Array))
        expect(rows.drop(cap).map { |row| row['messages'] }).to eq([nil, nil])
      end

      it 'reports the rows it left out' do
        allow(ForestAdminDatasourcePylon).to receive(:logger).and_return(logger)

        issues.list(nil, filter, %w[id messages])

        expect(logger).to have_received(:warn).with(/Asked for the message thread of #{cap + 2} issues/)
      end

      it 'reports nothing when the page fits under the cap' do
        allow(ForestAdminDatasourcePylon).to receive(:logger).and_return(logger)
        stub_issues(issue_payload('i1'))

        issues.list(nil, filter, %w[id messages])

        expect(logger).not_to have_received(:warn)
      end
    end

    describe 'when the thread cannot be read' do
      before { stub_issues(issue_payload('i1'), issue_payload('i2')) }

      it 'serves the page with the column left at nil' do
        stub_request(:get, "#{base}/issues/i1/messages").to_return(json({ 'message' => 'boom' }, 500))
        stub_messages('i2', message_payload('msg-2'))

        rows = issues.list(nil, filter, %w[id messages])

        expect(rows.map { |row| row['id'] }).to eq(%w[i1 i2])
        expect(rows.first['messages']).to be_nil
        expect(rows.last['messages'].map { |m| m['id'] }).to eq(%w[msg-2])
      end

      it 'reports the degradation' do
        allow(ForestAdminDatasourcePylon).to receive(:logger).and_return(logger)
        stub_request(:get, %r{/issues/i\d/messages}).to_return(json({ 'message' => 'boom' }, 500))

        issues.list(nil, filter, %w[id messages])

        expect(logger).to have_received(:warn).with(/fetch_issue_messages\(i1\) failed; degrading/)
      end
    end
  end
end
