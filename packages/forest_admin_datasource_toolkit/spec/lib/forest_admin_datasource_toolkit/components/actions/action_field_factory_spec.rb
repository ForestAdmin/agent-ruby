require 'spec_helper'

module ForestAdminDatasourceToolkit
  module Components
    module Actions
      describe ActionFieldFactory do
        describe 'when build_layout_element' do
          context 'when element is a separator' do
            let(:element) { { type: 'Layout', component: 'Separator' } }

            it 'returns a separator element' do
              result = described_class.build_layout_element(element)
              expect(result).to be_a(ActionLayoutElement::SeparatorElement)
            end
          end

          context 'when element is a HtmlBlock' do
            let(:element) { { type: 'Layout', component: 'HtmlBlock', content: '<p>foo</p>' } }

            it 'returns a html block element' do
              result = described_class.build_layout_element(element)
              expect(result).to be_a(ActionLayoutElement::HtmlBlockElement)
              expect(result.content).to eq('<p>foo</p>')
            end
          end
        end
      end
    end
  end
end
