require 'spec_helper'

module ForestAdminAgent
  module Routes
    include ForestAdminDatasourceToolkit::Schema
    include ForestAdminDatasourceToolkit::Components::Query::ConditionTree

    describe 'Permission and scope reads of a request' do
      include_context 'with caller'

      let(:readable) { %w[book person] }
      let(:refetched_readable) { readable }
      let(:users) { [{ id: 1, roleId: 1, permissionLevel: 'user' }] }
      let(:refetched_users) { users }
      let(:fetches) { Hash.new(0) }
      let(:reads) { Hash.new(0) }

      let(:fields) { { 'book' => 'id,title,author', 'author' => 'name' } }
      let(:filters) { JSON.generate(field: 'author:name', operator: 'present', value: nil) }

      let(:requests) do
        {
          'a list filtered and sorted on a relation' => lambda do
            Resources::List.new.handle_request(
              request('collection_name' => 'book', 'fields' => fields, 'filters' => filters, 'sort' => 'author.name')
            )
          end,
          'its count' => lambda do
            Resources::Count.new.handle_request(request('collection_name' => 'book', 'filters' => filters))
          end,
          'a get-one' => lambda do
            Resources::Show.new.handle_request(request('collection_name' => 'book', 'id' => '1'))
          end,
          'a related list' => lambda do
            Resources::Related::ListRelated.new.handle_request(
              request('collection_name' => 'person', 'id' => '1', 'relation_name' => 'books', 'fields' => fields)
            )
          end
        }
      end

      def request(params)
        { headers: { 'HTTP_AUTHORIZATION' => bearer }, params: params.merge('timezone' => 'Europe/Paris') }
      end

      def environment(readable_collections)
        enabled = { roles: [1] }
        crud = %i[browseEnabled editEnabled addEnabled deleteEnabled exportEnabled].to_h { |key| [key, enabled] }
        collections = %w[book person].to_h do |name|
          read = readable_collections.include?(name) ? enabled : { roles: [] }
          [name, { collection: crud.merge(readEnabled: read), actions: {} }]
        end

        { collections: collections }
      end

      def rendering
        {
          collections: {
            book: { scope: { field: 'title', operator: 'present', value: nil }, liveQuerySegments: [] },
            person: { scope: nil, liveQuerySegments: [] }
          },
          team: { id: 1, name: 'Operations' },
          stats: []
        }
      end

      before do
        datasource = ForestAdminDatasourceToolkit::Datasource.new
        datasource.add_collection(
          build_collection(
            name: 'book',
            schema: {
              fields: {
                'id' => build_numeric_primary_key(filter_operators: [Operators::EQUAL, Operators::IN]),
                'title' => build_column(column_type: 'String', filter_operators: [Operators::PRESENT]),
                'author_id' => build_column(column_type: 'Number', filter_operators: [Operators::EQUAL, Operators::IN]),
                'author' => build_many_to_one(foreign_collection: 'person', foreign_key: 'author_id')
              },
              countable: true
            }
          )
        )
        datasource.add_collection(
          build_collection(
            name: 'person',
            schema: {
              fields: {
                'id' => build_numeric_primary_key(filter_operators: [Operators::EQUAL, Operators::IN]),
                'name' => build_column(column_type: 'String', filter_operators: [Operators::PRESENT]),
                'books' => build_one_to_many(foreign_collection: 'book', origin_key: 'author_id', origin_key_target: 'id')
              }
            }
          )
        )

        allow(Builder::AgentFactory.instance).to receive(:send_schema).and_return(nil)
        Builder::AgentFactory.instance.add_datasource(datasource)
        Builder::AgentFactory.instance.build
        book = Facades::Container.datasource.get_collection('book')
        allow(book).to receive_messages(
          list: [{ 'id' => 1, 'title' => 'Dune', 'author_id' => 1, 'author' => { 'id' => 1, 'name' => 'Frank' } }],
          aggregate: [{ value: 1, group: [] }]
        )

        api = instance_double(Http::ForestAdminApiRequester)
        allow(api).to receive(:get) do |url|
          fetches[url] += 1
          body = case url
                 when '/liana/v4/permissions/environment'
                   environment(fetches[url] == 1 ? readable : refetched_readable)
                 when '/liana/v4/permissions/users'
                   fetches[url] == 1 ? users : refetched_users
                 else
                   rendering
                 end
          instance_double(Faraday::Response, body: body.to_json)
        end
        allow(Http::ForestAdminApiRequester).to receive(:new).and_return(api)

        allow(Utils::SafeFileCache).to receive(:new).and_wrap_original do |build, *args|
          build.call(*args).tap do |cache|
            allow(cache).to receive(:get).and_wrap_original do |original, key|
              reads[key] += 1
              original.call(key)
            end
          end
        end

        Services::Permissions.invalidate_cache
      end

      ['a list filtered and sorted on a relation', 'its count', 'a get-one', 'a related list'].each do |name|
        it "reads each key at most once for #{name}, on a cold then a warm cache" do
          2.times do
            reads.clear
            requests[name].call

            expect(reads.keys).to include('forest.collections', 'forest.users', 'forest.has_permission', '114')
            expect(reads.values).to all(eq(1))
          end
        end
      end

      context 'when a relation is denied by a stale cache' do
        let(:readable) { %w[book] }
        let(:refetched_readable) { %w[book person] }

        before { Services::Permissions.build_cache('permissions').set('forest.has_permission', { enable: true }) }

        it 'refetches once and answers the rest of the request from the fresh permissions' do
          result = requests['a list filtered and sorted on a relation'].call

          expect(result[:content]['included'].map { |record| record['type'] }).to include('person')
          expect(fetches['/liana/v4/permissions/environment']).to eq(2)
        end
      end

      context 'when the user is missing from a stale users cache' do
        let(:users) { [] }
        let(:refetched_users) { [{ id: 1, roleId: 1, permissionLevel: 'user' }] }

        it 'refetches the users once and authorizes the request' do
          requests['a list filtered and sorted on a relation'].call

          expect(fetches['/liana/v4/permissions/users']).to eq(2)
        end
      end
    end
  end
end
