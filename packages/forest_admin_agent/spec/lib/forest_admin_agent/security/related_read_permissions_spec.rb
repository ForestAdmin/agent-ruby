require 'spec_helper'

# Drives a real Permissions service rather than a double, so the guards themselves are under test
# and not the stubs the route specs install.
module ForestAdminAgent
  module Services
    include ForestAdminDatasourceToolkit
    include ForestAdminDatasourceToolkit::Schema
    include ForestAdminDatasourceToolkit::Components::Query
    include ForestAdminDatasourceToolkit::Components::Query::ConditionTree

    describe Permissions do
      include_context 'with caller'

      let(:datasource) { build_datasource_with_collections(collections) }
      let(:cards) { datasource.get_collection('cards') }

      let(:collections) do
        [
          build_collection(
            name: 'cards',
            schema: {
              fields: {
                'id' => build_numeric_primary_key,
                'pan_last4' => build_column(column_type: 'String'),
                'account_id' => build_column(column_type: 'Number'),
                'holder_id' => build_column(column_type: 'Number'),
                'holder_type' => build_column(column_type: 'String'),
                'account' => build_many_to_one(foreign_collection: 'accounts', foreign_key: 'account_id'),
                'holder' => Relations::PolymorphicManyToOneSchema.new(
                  foreign_key: 'holder_id',
                  foreign_key_type_field: 'holder_type',
                  foreign_collections: %w[persons companies],
                  foreign_key_targets: { 'persons' => 'id', 'companies' => 'id' }
                )
              }
            }
          ),
          build_collection(
            name: 'accounts',
            schema: {
              fields: {
                'id' => build_numeric_primary_key,
                'iban' => build_column(column_type: 'String', filter_operators: [Operators::EQUAL]),
                'organization_id' => build_column(column_type: 'Number'),
                'organization' => build_many_to_one(
                  foreign_collection: 'organizations', foreign_key: 'organization_id'
                )
              }
            }
          ),
          build_collection(
            name: 'organizations',
            schema: { fields: { 'id' => build_numeric_primary_key, 'name' => build_column(column_type: 'String', filter_operators: [Operators::EQUAL]) } }
          ),
          build_collection(
            name: 'persons',
            schema: { fields: { 'id' => build_numeric_primary_key, 'national_id' => build_column(column_type: 'String') } }
          ),
          build_collection(
            name: 'companies',
            schema: { fields: { 'id' => build_numeric_primary_key, 'siret' => build_column(column_type: 'String') } }
          )
        ]
      end

      # `cards` is always readable: the route asserts browse or read on it before any of this runs.
      def build_permissions(readable)
        permissions = described_class.new(caller)
        allow(permissions).to receive_messages(
          permission_system?: true,
          get_user_data: { id: 1, roleId: 7 },
          get_collections_permissions_data: (%w[cards] + readable).to_h { |name| [name.to_sym, { read: [7] }] }
                                            .merge(
                                              (%w[accounts organizations persons companies] - readable)
                                              .to_h { |name| [name.to_sym, { read: [] }] }
                                            )
        )

        permissions
      end

      describe 'without a permission system' do
        it 'keeps every path' do
          permissions = described_class.new(caller)
          allow(permissions).to receive(:permission_system?).and_return(false)

          projection = permissions.redact_projection(
            cards, Projection.new(%w[id account:iban holder:*]), named_by_caller: true
          )

          expect(projection).to eq(%w[id account:iban holder:*])
        end

        it 'refuses no filter' do
          permissions = described_class.new(caller)
          allow(permissions).to receive(:permission_system?).and_return(false)
          args = {
            headers: { 'HTTP_AUTHORIZATION' => bearer },
            params: {
              'collection_name' => 'cards',
              filters: { field: 'account:iban', operator: 'equal', value: 'FR76' }.to_json
            }
          }

          expect { permissions.assert_can_read_query_fields(cards, args) }.not_to raise_error
        end
      end

      describe '#redact_projection' do
        it 'refuses a field the caller named on a collection it cannot read' do
          permissions = build_permissions([])

          expect do
            permissions.redact_projection(cards, Projection.new(%w[id account:iban]), named_by_caller: true)
          end.to raise_error(
            ForestAdminAgent::Http::Exceptions::ForbiddenError,
            "You are not allowed to read 'account:iban' from the 'accounts' collection."
          )
        end

        it 'names every offending path in one message so a client retries once' do
          permissions = build_permissions([])

          expect do
            permissions.redact_projection(
              cards, Projection.new(%w[id account:iban account:organization:name]), named_by_caller: true
            )
          end.to raise_error(/'account:iban'.+'accounts'.+'account:organization:name'.+'organizations'/)
        end

        it 'drops the path instead when the caller never named it' do
          permissions = build_permissions([])

          projection = permissions.redact_projection(
            cards, Projection.new(%w[id pan_last4 account:iban]), named_by_caller: false
          )

          expect(projection).to eq(%w[id pan_last4])
        end

        it 'traverses a collection it cannot read to reach a column it can' do
          permissions = build_permissions(%w[organizations])

          projection = permissions.redact_projection(
            cards, Projection.new(%w[id account:organization:name]), named_by_caller: true
          )

          expect(projection).to eq(%w[id account:organization:name])
        end

        it 'keeps a polymorphic relation whose every target is readable' do
          permissions = build_permissions(%w[persons companies])

          projection = permissions.redact_projection(cards, Projection.new(%w[id holder:*]), named_by_caller: false)

          expect(projection).to eq(%w[id holder:*])
        end

        it 'refuses a polymorphic relation when a single target is denied' do
          permissions = build_permissions(%w[persons])

          expect do
            permissions.redact_projection(cards, Projection.new(%w[id holder:*]), named_by_caller: true)
          end.to raise_error(
            ForestAdminAgent::Http::Exceptions::ForbiddenError,
            "You are not allowed to read 'holder:*' from the 'persons' or 'companies' collection."
          )
        end

        it 'leaves nothing for `with_pks` to re-add once the redaction emptied a relation' do
          permissions = build_permissions([])

          projection = permissions.redact_projection(
            cards, Projection.new(%w[id account:iban]), named_by_caller: false
          ).with_pks(cards)

          expect(projection).to eq(%w[id])
        end

        # The key of a collection the caller cannot read stays, because the serializer needs it to
        # emit the readable column behind it — dropping it would take the permitted path down too.
        it 'keeps the key `with_pks` needs to serialize a path the redaction kept' do
          permissions = build_permissions(%w[organizations])

          projection = permissions.redact_projection(
            cards, Projection.new(%w[id account:organization:name]), named_by_caller: true
          ).with_pks(cards)

          expect(projection).to include('account:id', 'account:organization:id')
        end

        context 'when a polymorphic relation declares no target at all' do
          let(:orphan_cards) do
            build_datasource_with_collections(
              [
                build_collection(
                  name: 'cards',
                  schema: {
                    fields: {
                      'id' => build_numeric_primary_key,
                      'holder_id' => build_column(column_type: 'Number'),
                      'holder_type' => build_column(column_type: 'String'),
                      'holder' => Relations::PolymorphicManyToOneSchema.new(
                        foreign_key: 'holder_id',
                        foreign_key_type_field: 'holder_type',
                        foreign_collections: [],
                        foreign_key_targets: {}
                      )
                    }
                  }
                )
              ]
            ).get_collection('cards')
          end

          it 'refuses the path the caller named rather than allowing what resolves to nothing' do
            permissions = build_permissions([])

            expect do
              permissions.redact_projection(orphan_cards, Projection.new(%w[id holder:*]), named_by_caller: true)
            end.to raise_error(
              ForestAdminAgent::Http::Exceptions::ForbiddenError,
              "You are not allowed to read 'holder:*' from an unresolved polymorphic relation."
            )
          end

          it 'drops the path from the default expansion' do
            permissions = build_permissions([])

            projection = permissions.redact_projection(
              orphan_cards, Projection.new(%w[id holder:*]), named_by_caller: false
            )

            expect(projection).to eq(%w[id])
          end
        end

        it 'drops a polymorphic relation with a denied target from the default expansion' do
          permissions = build_permissions(%w[persons])

          projection = permissions.redact_projection(
            cards, ProjectionFactory.all(cards), named_by_caller: false
          )

          expect(projection).not_to include('holder:*')
          expect(projection).to include('id', 'pan_last4', 'holder_type')
        end
      end

      describe '#assert_can_read_query_fields' do
        def args_with(params)
          { headers: { 'HTTP_AUTHORIZATION' => bearer }, params: { 'collection_name' => 'cards' }.merge(params) }
        end

        it 'refuses a filter on a collection the caller cannot read' do
          permissions = build_permissions([])
          args = args_with(filters: { field: 'account:iban', operator: 'equal', value: 'FR76' }.to_json)

          expect { permissions.assert_can_read_query_fields(cards, args) }.to raise_error(
            ForestAdminAgent::Http::Exceptions::ForbiddenError,
            "You cannot filter on 'account:iban': you are not allowed to read the 'accounts' collection."
          )
        end

        it 'refuses a sort on a collection the caller cannot read' do
          permissions = build_permissions([])

          expect { permissions.assert_can_read_query_fields(cards, args_with(sort: '-account.iban')) }
            .to raise_error(
              ForestAdminAgent::Http::Exceptions::ForbiddenError,
              "You cannot sort on 'account:iban': you are not allowed to read the 'accounts' collection."
            )
        end

        # `for_each_leaf` on a branch replaces each condition with the block's return value, so the
        # tree the guard walked is the one asserted on — a freshly parsed one could not catch it.
        it 'leaves the branch it walked intact instead of rebuilding it from the guard' do
          permissions = build_permissions(%w[accounts])
          args = args_with(
            filters: {
              aggregator: 'and',
              conditions: [
                { field: 'account:iban', operator: 'equal', value: 'FR76' },
                { field: 'id', operator: 'equal', value: 1 }
              ]
            }.to_json
          )
          tree = ForestAdminAgent::Utils::QueryStringParser.parse_condition_tree(cards, args)
          allow(ForestAdminAgent::Utils::QueryStringParser).to receive(:parse_condition_tree).and_return(tree)

          permissions.assert_can_read_query_fields(cards, args)

          expect(tree.conditions.map(&:field)).to eq(%w[account:iban id])
        end

        def searchable_cards(searched)
          double = instance_double(
            ForestAdminDatasourceToolkit::Decorators::CollectionDecorator,
            name: 'cards',
            schema: cards.schema.merge(searchable: true),
            is_searchable?: true,
            datasource: datasource
          )
          allow(double).to receive(:searched_fields).and_return(searched)

          double
        end

        it 'refuses whatever the stack says the search will reach' do
          permissions = build_permissions([])
          collection = searchable_cards([{ path: 'holder:national_id', collections: ['persons'] }])

          expect { permissions.assert_can_read_query_fields(collection, args_with(search: 'martin')) }
            .to raise_error(
              ForestAdminAgent::Http::Exceptions::ForbiddenError,
              "You cannot search on 'holder:national_id': you are not allowed to read the 'persons' collection."
            )
        end

        it 'accepts a search once every collection the stack names is readable' do
          permissions = build_permissions(%w[persons])
          collection = searchable_cards([{ path: 'holder:national_id', collections: ['persons'] }])

          expect { permissions.assert_can_read_query_fields(collection, args_with(search: 'martin')) }
            .not_to raise_error
        end

        # Below publication, so the permission payload has never heard of it: unpublished, not denied.
        it 'ignores a search target the datasource stopped publishing' do
          permissions = build_permissions([])
          collection = searchable_cards([{ path: 'account:iban', collections: ['accounts'] }])
          published = datasource.collections.except('accounts')
          allow(datasource).to receive(:collections).and_return(published)

          expect { permissions.assert_can_read_query_fields(collection, args_with(search: 'martin')) }
            .not_to raise_error
        end

        # A replaced search: the handler picks the fields, the caller only supplies the text.
        it 'serves the request when the stack cannot say what a search reaches' do
          permissions = build_permissions([])

          expect { permissions.assert_can_read_query_fields(searchable_cards(nil), args_with(search: 'martin')) }
            .not_to raise_error
        end

        # The chart routes ignore `search`, so parsing it here must not turn it into a 400.
        it 'ignores a search on a collection that has none' do
          permissions = build_permissions([])

          expect { permissions.assert_can_read_query_fields(cards, args_with(search: 'martin')) }
            .not_to raise_error
        end

        # A count applies no sort, so refusing one would refuse a request the denied field cannot
        # reach. Same shape on the chart routes, which apply neither sort nor search.
        it 'ignores a query component the route does not apply' do
          permissions = build_permissions([])

          expect do
            permissions.assert_can_read_query_fields(
              cards, args_with(sort: '-account.iban'), consumes: %i[filter search]
            )
          end.not_to raise_error
        end

        it 'accepts a filter once the collection it reaches is readable' do
          permissions = build_permissions(%w[accounts])
          args = args_with(filters: { field: 'account:iban', operator: 'equal', value: 'FR76' }.to_json)

          expect { permissions.assert_can_read_query_fields(cards, args) }.not_to raise_error
        end
      end

      describe '#read_permissions' do
        def with_instant_cache_refresh(enabled)
          config = ForestAdminAgent::Facades::Container.config_from_cache.merge(instant_cache_refresh: enabled)
          allow(ForestAdminAgent::Facades::Container).to receive(:config_from_cache).and_return(config)
        end

        it 'answers a collection once for the whole request' do
          with_instant_cache_refresh(true)
          permissions = build_permissions(%w[accounts])

          permissions.read_permissions('cards', %w[accounts])
          permissions.read_permissions('cards', %w[accounts])

          expect(permissions).to have_received(:get_collections_permissions_data).once
        end

        # Denial is the steady state here, and `refresh-roles` on the SSE channel already evicts on a
        # role change: a role that simply lacks `read` must not cost a permission fetch, and a cache
        # eviction every other in-flight request reads through, on each page load.
        it 'does not refetch for a denial the cached payload accounts for while the channel is up' do
          with_instant_cache_refresh(true)
          permissions = build_permissions([])

          expect(permissions.read_permissions('cards', %w[accounts])).to eq(
            { 'cards' => true, 'accounts' => false }
          )
          expect(permissions).not_to have_received(:get_collections_permissions_data).with(force_fetch: true)
        end

        # `instant_cache_refresh` defaults to production only, so outside it nothing else keeps the
        # cache fresh and a newly granted `read` would stay redacted until the cache expires.
        it 'refetches a denial when no channel keeps the cache fresh' do
          with_instant_cache_refresh(false)
          permissions = build_permissions([])

          permissions.read_permissions('cards', %w[accounts])

          expect(permissions).to have_received(:get_collections_permissions_data).with(force_fetch: true).once
        end

        it 'refetches once for the whole request when the payload does not know a collection' do
          with_instant_cache_refresh(true)
          permissions = build_permissions([])

          permissions.read_permissions('cards', %w[not_in_payload])
          permissions.read_permissions('cards', %w[another_one_missing])

          expect(permissions).to have_received(:get_collections_permissions_data).with(force_fetch: true).once
        end

        it 'answers without a fetch once the permission system is absent' do
          permissions = described_class.new(caller)
          allow(permissions).to receive_messages(permission_system?: false)

          expect(permissions.read_permissions('cards', %w[accounts])).to eq(
            { 'cards' => true, 'accounts' => true }
          )
        end
      end
    end
  end
end
