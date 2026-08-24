require 'spec_helper'

module ForestAdminAgent
  module Utils
    include ForestAdminDatasourceToolkit::Components::Query

    describe CsvGenerator do
      let(:projection) { Projection.new(%w[id last_name first_name email active created_at updated_at address:planet]) }
      let(:records) do
        [
          {
            'id' => 1,
            'last_name' => 'Skywalker',
            'first_name' => 'Luke',
            'email' => 'luke@sw.com',
            'active' => true,
            'created_at' => '2024-05-21T00:00:00.000Z',
            'updated_at' => '2024-05-21T00:00:00.000Z',
            'address_id' => 1,
            'address' => { 'id' => 1, 'planet' => 'Tatooine' }
          },
          {
            'id' => 2,
            'last_name' => 'Solo',
            'first_name' => 'Han',
            'email' => 'han@sw.com',
            'active' => true,
            'created_at' => '2024-05-21T00:00:00.000Z',
            'updated_at' => '2024-05-21T00:00:00.000Z',
            'address_id' => 2,
            'address' => { 'id' => 2, 'planet' => 'Corellia' }
          },
          {
            'id' => 3,
            'last_name' => 'Organa',
            'first_name' => 'Leia',
            'email' => 'leia@sw.com',
            'active' => true,
            'created_at' => '2024-05-21T00:00:00.000Z',
            'updated_at' => '2024-05-21T00:00:00.000Z',
            'address_id' => 3,
            'address' => { 'id' => 3, 'planet' => 'Alderaan' }
          },
          {
            'id' => 4,
            'last_name' => 'Kenobi',
            'first_name' => 'Obi-Wan',
            'email' => 'obiwan@sw.com',
            'active' => false,
            'created_at' => '2024-05-21T00:00:00.000Z',
            'updated_at' => '2024-05-21T00:00:00.000Z',
            'address_id' => 4,
            'address' => { 'id' => 4, 'planet' => 'Stewjon' }
          }
        ]
      end

      let(:data) do
        {
          'id' => [1, 2, 3, 4],
          'last_name' => %w[Skywalker Solo Organa Kenobi],
          'first_name' => %w[Luke Han Leia Obi-Wan],
          'email' => %w[luke@sw.com han@sw.com leia@sw.com obiwan@sw.com],
          'active' => [true, true, true, false],
          'created_at' => %w[2024-05-21T00:00:00.000Z 2024-05-21T00:00:00.000Z 2024-05-21T00:00:00.000Z 2024-05-21T00:00:00.000Z],
          'updated_at' => %w[2024-05-21T00:00:00.000Z 2024-05-21T00:00:00.000Z 2024-05-21T00:00:00.000Z 2024-05-21T00:00:00.000Z],
          'address' => %w[Tatooine Corellia Alderaan Stewjon]
        }
      end

      let(:response) do
        "id,last_name,first_name,email,active,created_at,updated_at,address\n1,Skywalker,Luke,luke@sw.com,true,2024-05-21T00:00:00.000Z,2024-05-21T00:00:00.000Z,Tatooine\n2,Solo,Han,han@sw.com,true,2024-05-21T00:00:00.000Z,2024-05-21T00:00:00.000Z,Corellia\n3,Organa,Leia,leia@sw.com,true,2024-05-21T00:00:00.000Z,2024-05-21T00:00:00.000Z,Alderaan\n4,Kenobi,Obi-Wan,obiwan@sw.com,false,2024-05-21T00:00:00.000Z,2024-05-21T00:00:00.000Z,Stewjon\n"
      end

      describe 'filter_header' do
        let(:requested) { Projection.new(%w[id last_name address:planet]) }

        it 'hands the header back untouched when the redaction dropped nothing' do
          expect(described_class.filter_header('Id,Last name,Planet', requested, requested))
            .to eq('Id,Last name,Planet')
        end

        it 'returns nothing when the caller sent no header' do
          expect(described_class.filter_header(nil, requested, Projection.new(%w[id]))).to be_nil
        end

        it 'drops the label of a path the redaction removed from a comma-joined header' do
          kept = Projection.new(%w[id last_name])

          expect(described_class.filter_header('Id,Last name,Planet', requested, kept))
            .to eq(['Id', 'Last name'])
        end

        it 'drops the label of a path the redaction removed from a JSON header' do
          kept = Projection.new(%w[id address:planet])

          expect(described_class.filter_header('["Id","Last name","Planet"]', requested, kept))
            .to eq(%w[Id Planet])
        end

        it 'drops the label of a path the redaction removed from an array of labels' do
          kept = Projection.new(%w[address:planet])

          expect(described_class.filter_header(['Id', 'Last name', 'Planet'], requested, kept))
            .to eq(['Planet'])
        end

        # `fields[books]=author,id,title` with `fields[author]=firstName,lastName` expands into four
        # paths against three labels: filtering by position drops "Id" and keeps "Title", leaving one
        # label for two data columns, under the wrong name.
        it 'hands back a JSON header the expanded projection has outgrown' do
          expanded = Projection.new(%w[author:firstName author:lastName id title])
          kept = Projection.new(%w[id title])

          expect(described_class.filter_header('["Author","Id","Title"]', expanded, kept))
            .to eq('["Author","Id","Title"]')
        end

        it 'hands back a header that carries no label for each exported column' do
          # `fields[users]=address,id` expands `address` into two paths, so no label sits at the
          # index of a path and dropping one by position would mislabel the rest.
          expanded = Projection.new(%w[address:planet address:city id])

          expect(described_class.filter_header('Address,Id', expanded, Projection.new(%w[id])))
            .to eq('Address,Id')
        end
      end

      describe 'generate' do
        it 'generates a CSV string' do
          csv = described_class.generate(records, projection)
          expect(csv).to eq(response)
        end
      end

      describe 'generate_csv_string' do
        it 'generates a CSV string' do
          csv = described_class.generate_csv_string(data)
          expect(csv).to eq(response)
        end
      end
    end
  end
end
