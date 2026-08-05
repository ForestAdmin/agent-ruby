require 'spec_helper'

module ForestAdminDatasourceGraphqlHasura
  RSpec.describe Datasource do
    describe 'Rails polymorphism' do
      context 'with the Hasura metadata API available' do
        subject(:datasource) { BankingSchema.build_datasource }

        it 'registers the collections under their Rails class names' do
          expect(datasource.collections.keys).to contain_exactly('Comment', 'Transfer', 'Card', 'Membership')
        end

        it 'emits a PolymorphicManyToOne for the commentable association' do
          field = datasource.get_collection('Comment').schema[:fields]['commentable']

          expect(field.type).to eq('PolymorphicManyToOne')
          expect(field.foreign_key).to eq('commentable_id')
          expect(field.foreign_key_type_field).to eq('commentable_type')
          expect(field.foreign_collections).to contain_exactly('Transfer', 'Card')
          expect(field.foreign_key_targets).to eq({ 'Transfer' => 'id', 'Card' => 'id' })
        end

        it 'does not expose the per-target Hasura relationships as ManyToOne' do
          fields = datasource.get_collection('Comment').schema[:fields]

          expect(fields).not_to have_key('transfer')
          expect(fields).not_to have_key('card')
        end

        it 'ignores the Hasura <relation>_aggregate companion fields' do
          fields = datasource.get_collection('Transfer').schema[:fields]

          expect(fields).not_to have_key('comments_aggregate')
        end

        it 'marks the polymorphic discriminator columns as read-only' do
          fields = datasource.get_collection('Comment').schema[:fields]

          expect(fields['commentable_id'].is_read_only).to be(true)
          expect(fields['commentable_type'].is_read_only).to be(true)
        end

        it 'emits a matching PolymorphicOneToMany on each target' do
          transfer_comments = datasource.get_collection('Transfer').schema[:fields]['comments']
          card_comments = datasource.get_collection('Card').schema[:fields]['comments']

          expect(transfer_comments.type).to eq('PolymorphicOneToMany')
          expect(transfer_comments.foreign_collection).to eq('Comment')
          expect(transfer_comments.origin_key).to eq('commentable_id')
          expect(transfer_comments.origin_key_target).to eq('id')
          expect(transfer_comments.origin_type_field).to eq('commentable_type')
          expect(transfer_comments.origin_type_value).to eq('Transfer')
          expect(card_comments.origin_type_value).to eq('Card')
        end

        it 'pairs both sides so the toolkit resolves the inverse relation' do
          inverse = ForestAdminDatasourceToolkit::Utils::Collection.get_inverse_relation(
            datasource.get_collection('Transfer'), 'comments'
          )

          expect(inverse).to eq('commentable')
        end

        it 'keeps the regular belongs_to as a plain ManyToOne' do
          field = datasource.get_collection('Comment').schema[:fields]['membership']

          expect(field.type).to eq('ManyToOne')
          expect(field.foreign_collection).to eq('Membership')
          expect(field.foreign_key).to eq('membership_id')
          expect(field.foreign_key_target).to eq('id')
        end

        it 'detects primary keys from the _by_pk queries' do
          fields = datasource.get_collection('Comment').schema[:fields]

          expect(fields['id'].is_primary_key).to be(true)
          expect(fields['body'].is_primary_key).to be(false)
        end
      end

      context 'when the metadata API is blocked (production setup)' do
        it 'does not crash and keeps the discriminator columns as plain fields' do
          datasource = BankingSchema.build_datasource(metadata_blocked: true)
          fields = datasource.get_collection('Comment').schema[:fields]

          expect(fields['commentable_type'].type).to eq('Column')
          expect(fields['commentable_id'].type).to eq('Column')
          expect(fields).not_to have_key('commentable')
        end

        it 'skips relationships whose foreign key cannot be inferred instead of crashing' do
          datasource = BankingSchema.build_datasource(metadata_blocked: true)
          fields = datasource.get_collection('Comment').schema[:fields]

          expect(fields).not_to have_key('transfer')
          expect(fields).not_to have_key('card')
        end

        # A configured association without its column pair would emit a relation
        # referencing columns that do not exist and break the collection.
        it 'ignores a configured polymorphic relation whose discriminator columns are missing' do
          datasource = BankingSchema.build_datasource(
            metadata_blocked: true,
            polymorphic_relations: { 'transfers' => { 'ownable' => %w[cards] } }
          )

          expect(datasource.get_collection('Transfer').schema[:fields]).not_to have_key('ownable')
        end

        it 'still emits the polymorphic relations when declared in the configuration' do
          datasource = BankingSchema.build_datasource(
            metadata_blocked: true,
            polymorphic_relations: { 'comments' => { 'commentable' => %w[transfers cards] } }
          )

          commentable = datasource.get_collection('Comment').schema[:fields]['commentable']
          transfer_comments = datasource.get_collection('Transfer').schema[:fields]['comments']

          expect(commentable.type).to eq('PolymorphicManyToOne')
          expect(commentable.foreign_collections).to contain_exactly('Transfer', 'Card')
          expect(transfer_comments.type).to eq('PolymorphicOneToMany')
          expect(transfer_comments.origin_type_value).to eq('Transfer')
        end
      end

      context 'with namespaced Rails models' do
        it 'uses the configured type value and formats the collection name' do
          datasource = BankingSchema.build_datasource(type_values: { 'transfers' => 'Banking::Transfer' })

          expect(datasource.collections.keys).to include('Banking__Transfer')

          commentable = datasource.get_collection('Comment').schema[:fields]['commentable']
          expect(commentable.foreign_collections).to contain_exactly('Banking__Transfer', 'Card')
          expect(commentable.foreign_key_targets).to include('Banking__Transfer' => 'id')

          comments = datasource.get_collection('Banking__Transfer').schema[:fields]['comments']
          expect(comments.origin_type_value).to eq('Banking::Transfer')
        end
      end
    end
  end
end
