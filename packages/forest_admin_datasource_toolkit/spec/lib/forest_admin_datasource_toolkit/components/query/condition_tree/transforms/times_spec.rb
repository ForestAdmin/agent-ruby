require 'spec_helper'
require 'active_support/all'
require 'active_support/core_ext/numeric/time'

module ForestAdminDatasourceToolkit
  module Components
    module Query
      module ConditionTree
        module Transforms
          include ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes

          describe Times do
            subject(:times) { described_class }

            let(:tz) { 'Europe/Paris' }

            # Thursday 2026-05-14 00:30 in Paris, still 2026-05-13 in UTC
            around { |example| travel_to(Time.utc(2026, 5, 13, 22, 30)) { example.run } }

            def rewrite(operator, value = nil)
              times.transforms[operator][0][:replacer].call(ConditionTreeLeaf.new('column', operator, value), tz).to_h
            end

            def leaf(operator, value)
              ConditionTreeLeaf.new('column', operator, value).to_h
            end

            def between(greater_than, less_than)
              ConditionTreeBranch.new('And', [
                                        ConditionTreeLeaf.new('column', Operators::GREATER_THAN, greater_than),
                                        ConditionTreeLeaf.new('column', Operators::LESS_THAN, less_than)
                                      ]).to_h
            end

            it 'Before should rewrite' do
              expect(rewrite(Operators::BEFORE, Time.now)).to eq(leaf(Operators::LESS_THAN, '2026-05-13T22:30:00Z'))
            end

            it 'After should rewrite' do
              expect(rewrite(Operators::AFTER, Time.now)).to eq(leaf(Operators::GREATER_THAN, '2026-05-13T22:30:00Z'))
            end

            it 'Past should rewrite' do
              expect(rewrite(Operators::PAST)).to eq(leaf(Operators::LESS_THAN, '2026-05-13T22:30:00Z'))
            end

            it 'Future should rewrite' do
              expect(rewrite(Operators::FUTURE)).to eq(leaf(Operators::GREATER_THAN, '2026-05-13T22:30:00Z'))
            end

            it 'BeforeXHoursAgo should rewrite' do
              expect(rewrite(Operators::BEFORE_X_HOURS_AGO, 24))
                .to eq(leaf(Operators::LESS_THAN, '2026-05-12T22:30:00Z'))
            end

            it 'AfterXHoursAgo should rewrite' do
              expect(rewrite(Operators::AFTER_X_HOURS_AGO, 24))
                .to eq(leaf(Operators::GREATER_THAN, '2026-05-12T22:30:00Z'))
            end

            it 'PreviousMonthToDate should rewrite' do
              expect(rewrite(Operators::PREVIOUS_MONTH_TO_DATE))
                .to eq(between('2026-04-30T22:00:00Z', '2026-05-13T22:30:00Z'))
            end

            it 'PreviousMonth should rewrite' do
              expect(rewrite(Operators::PREVIOUS_MONTH)).to eq(between('2026-03-31T22:00:00Z', '2026-04-30T22:00:00Z'))
            end

            it 'PreviousQuarterToDate should rewrite' do
              expect(rewrite(Operators::PREVIOUS_QUARTER_TO_DATE))
                .to eq(between('2026-03-31T22:00:00Z', '2026-05-13T22:30:00Z'))
            end

            it 'PreviousQuarter should rewrite' do
              expect(rewrite(Operators::PREVIOUS_QUARTER)).to eq(between('2025-12-31T23:00:00Z', '2026-03-31T22:00:00Z'))
            end

            it 'PreviousWeekToDate should rewrite' do
              expect(rewrite(Operators::PREVIOUS_WEEK_TO_DATE))
                .to eq(between('2026-05-10T22:00:00Z', '2026-05-13T22:30:00Z'))
            end

            it 'PreviousWeek should rewrite' do
              expect(rewrite(Operators::PREVIOUS_WEEK)).to eq(between('2026-05-03T22:00:00Z', '2026-05-10T22:00:00Z'))
            end

            it 'PreviousXDaysToDate should rewrite' do
              expect(rewrite(Operators::PREVIOUS_X_DAYS_TO_DATE, 14))
                .to eq(between('2026-04-29T22:00:00Z', '2026-05-13T22:30:00Z'))
            end

            it 'PreviousXDays should rewrite' do
              expect(rewrite(Operators::PREVIOUS_X_DAYS, 14))
                .to eq(between('2026-04-29T22:00:00Z', '2026-05-13T22:00:00Z'))
            end

            it 'PreviousYearToDate should rewrite' do
              expect(rewrite(Operators::PREVIOUS_YEAR_TO_DATE))
                .to eq(between('2025-12-31T23:00:00Z', '2026-05-13T22:30:00Z'))
            end

            it 'PreviousYear should rewrite' do
              expect(rewrite(Operators::PREVIOUS_YEAR)).to eq(between('2024-12-31T23:00:00Z', '2025-12-31T23:00:00Z'))
            end

            it 'Today should rewrite' do
              expect(rewrite(Operators::TODAY)).to eq(between('2026-05-13T22:00:00Z', '2026-05-14T22:00:00Z'))
            end

            it 'Yesterday should rewrite' do
              expect(rewrite(Operators::YESTERDAY)).to eq(between('2026-05-12T22:00:00Z', '2026-05-13T22:00:00Z'))
            end
          end

          describe Times, 'when midnight passes during a rewrite' do
            it 'derives both bounds of Today from a single reading of the clock' do
              allow(Time).to receive(:now).and_return(Time.utc(2026, 5, 13, 21, 59, 59.999r), Time.utc(2026, 5, 13, 22))

              expect(described_class.transforms[Operators::TODAY][0][:replacer].call(
                ConditionTreeLeaf.new('column', Operators::TODAY), 'Europe/Paris'
              ).to_h)
                .to eq(ConditionTreeBranch.new('And', [
                                                 ConditionTreeLeaf.new('column', Operators::GREATER_THAN, '2026-05-12T22:00:00Z'),
                                                 ConditionTreeLeaf.new('column', Operators::LESS_THAN, '2026-05-13T22:00:00Z')
                                               ]).to_h)
            end
          end
        end
      end
    end
  end
end
