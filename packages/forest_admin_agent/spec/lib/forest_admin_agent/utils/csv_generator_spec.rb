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
