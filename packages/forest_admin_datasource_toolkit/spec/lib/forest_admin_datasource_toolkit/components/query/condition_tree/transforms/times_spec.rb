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

            before do
              @times = times.transforms
            end

            it 'Before should rewrite' do
              expect(@times[Operators::BEFORE][0][:replacer].call(
                       ConditionTreeLeaf.new('column', Operators::BEFORE, Time.now), 'Europe/Paris'
                     ))
                .to eq(ConditionTreeLeaf.new('column', Operators::LESS_THAN, times.format(Time.now)))
            end

            it 'After should rewrite' do
              expect(@times[Operators::AFTER][0][:replacer].call(
                       ConditionTreeLeaf.new('column', Operators::AFTER, Time.now), 'Europe/Paris'
                     ))
                .to eq(ConditionTreeLeaf.new('column', Operators::GREATER_THAN, times.format(Time.now)))
            end

            it 'Past should rewrite' do
              expect(@times[Operators::PAST][0][:replacer].call(
                       ConditionTreeLeaf.new('column', Operators::PAST, Time.now), 'Europe/Paris'
                     ))
                .to eq(ConditionTreeLeaf.new('column', Operators::LESS_THAN, times.format(Time.now)))
            end

            it 'Future should rewrite' do
              expect(@times[Operators::FUTURE][0][:replacer].call(
                       ConditionTreeLeaf.new('column', Operators::FUTURE, Time.now), 'Europe/Paris'
                     ))
                .to eq(ConditionTreeLeaf.new('column', Operators::GREATER_THAN, times.format(Time.now)))
            end

            it 'BeforeXHoursAgo should rewrite' do
              expect(@times[Operators::BEFORE_X_HOURS_AGO][0][:replacer].call(
                       ConditionTreeLeaf.new('column', Operators::BEFORE_X_HOURS_AGO, 24), 'Europe/Paris'
                     ))
                .to eq(ConditionTreeLeaf.new('column', Operators::LESS_THAN, times.format(24.hours.ago)))
            end

            it 'AfterXHoursAgo should rewrite' do
              expect(@times[Operators::AFTER_X_HOURS_AGO][0][:replacer].call(
                       ConditionTreeLeaf.new('column', Operators::AFTER_X_HOURS_AGO, 24), 'Europe/Paris'
                     ))
                .to eq(ConditionTreeLeaf.new('column', Operators::GREATER_THAN, times.format(24.hours.ago)))
            end

            it 'PreviousMonthToDate should rewrite' do
              expect(@times[Operators::PREVIOUS_MONTH_TO_DATE][0][:replacer].call(
                       ConditionTreeLeaf.new('column', Operators::PREVIOUS_MONTH_TO_DATE), 'Europe/Paris'
                     ))
                .to eq(ConditionTreeBranch.new('And', [
                                                 ConditionTreeLeaf.new('column', Operators::GREATER_THAN,
                                                                       times.format(Time.now.beginning_of_month)),
                                                 ConditionTreeLeaf.new('column', Operators::LESS_THAN,
                                                                       times.format(Time.now))
                                               ]))
            end

            it 'PreviousMonth should rewrite' do
              expect(@times[Operators::PREVIOUS_MONTH][0][:replacer].call(
                       ConditionTreeLeaf.new('column', Operators::PREVIOUS_MONTH), 'Europe/Paris'
                     ))
                .to eq(ConditionTreeBranch.new('And', [
                                                 ConditionTreeLeaf.new('column', Operators::GREATER_THAN,
                                                                       times.format(Time.now.beginning_of_month)),
                                                 ConditionTreeLeaf.new('column', Operators::LESS_THAN,
                                                                       times.format(Time.now))
                                               ]))
            end

            it 'PreviousQuarterToDate should rewrite' do
              expect(@times[Operators::PREVIOUS_QUARTER_TO_DATE][0][:replacer].call(
                       ConditionTreeLeaf.new('column', Operators::PREVIOUS_QUARTER_TO_DATE), 'Europe/Paris'
                     ))
                .to eq(ConditionTreeBranch.new('And', [
                                                 ConditionTreeLeaf.new('column', Operators::GREATER_THAN,
                                                                       times.format(Time.now.beginning_of_quarter)),
                                                 ConditionTreeLeaf.new('column', Operators::LESS_THAN,
                                                                       times.format(Time.now))
                                               ]))
            end

            it 'PreviousQuarter should rewrite' do
              expect(@times[Operators::PREVIOUS_QUARTER][0][:replacer].call(
                       ConditionTreeLeaf.new('column', Operators::PREVIOUS_QUARTER), 'Europe/Paris'
                     ))
                .to eq(ConditionTreeBranch.new('And', [
                                                 ConditionTreeLeaf.new('column', Operators::GREATER_THAN,
                                                                       times.format(Time.now.prev_quarter.beginning_of_quarter)),
                                                 ConditionTreeLeaf.new('column', Operators::LESS_THAN,
                                                                       times.format(Time.now.beginning_of_quarter))
                                               ]))
            end

            it 'PreviousWeekToDate should rewrite' do
              expect(@times[Operators::PREVIOUS_WEEK_TO_DATE][0][:replacer].call(
                       ConditionTreeLeaf.new('column', Operators::PREVIOUS_WEEK_TO_DATE), 'Europe/Paris'
                     ))
                .to eq(ConditionTreeBranch.new('And', [
                                                 ConditionTreeLeaf.new('column', Operators::GREATER_THAN,
                                                                       times.format(Time.now.beginning_of_week)),
                                                 ConditionTreeLeaf.new('column', Operators::LESS_THAN,
                                                                       times.format(Time.now))
                                               ]))
            end

            it 'PreviousWeek should rewrite' do
              expect(@times[Operators::PREVIOUS_WEEK][0][:replacer].call(
                       ConditionTreeLeaf.new('column', Operators::PREVIOUS_WEEK), 'Europe/Paris'
                     ))
                .to eq(ConditionTreeBranch.new('And', [
                                                 ConditionTreeLeaf.new('column', Operators::GREATER_THAN,
                                                                       times.format(Time.now.prev_week.beginning_of_week)),
                                                 ConditionTreeLeaf.new('column', Operators::LESS_THAN,
                                                                       times.format(Time.now.beginning_of_week))
                                               ]))
            end

            it 'PreviousXDaysToDate should rewrite' do
              expect(@times[Operators::PREVIOUS_X_DAYS_TO_DATE][0][:replacer].call(
                       ConditionTreeLeaf.new('column', Operators::PREVIOUS_X_DAYS_TO_DATE, 14), 'Europe/Paris'
                     ))
                .to eq(ConditionTreeBranch.new('And', [
                                                 ConditionTreeLeaf.new('column', Operators::GREATER_THAN,
                                                                       times.format(14.days.ago.beginning_of_day)),
                                                 ConditionTreeLeaf.new('column', Operators::LESS_THAN,
                                                                       times.format(Time.now))
                                               ]))
            end

            it 'PreviousXDays should rewrite' do
              expect(@times[Operators::PREVIOUS_X_DAYS][0][:replacer].call(
                       ConditionTreeLeaf.new('column', Operators::PREVIOUS_X_DAYS, 14), 'Europe/Paris'
                     ))
                .to eq(ConditionTreeBranch.new('And', [
                                                 ConditionTreeLeaf.new('column', Operators::GREATER_THAN,
                                                                       times.format(14.days.ago.beginning_of_day)),
                                                 ConditionTreeLeaf.new('column', Operators::LESS_THAN,
                                                                       times.format(Time.now.beginning_of_day))
                                               ]))
            end

            it 'PreviousYearToDate should rewrite' do
              expect(@times[Operators::PREVIOUS_YEAR_TO_DATE][0][:replacer].call(
                       ConditionTreeLeaf.new('column', Operators::PREVIOUS_YEAR_TO_DATE), 'Europe/Paris'
                     ))
                .to eq(ConditionTreeBranch.new('And', [
                                                 ConditionTreeLeaf.new('column', Operators::GREATER_THAN,
                                                                       times.format(Time.now.beginning_of_year)),
                                                 ConditionTreeLeaf.new('column', Operators::LESS_THAN,
                                                                       times.format(Time.now))
                                               ]))
            end

            it 'PreviousYear should rewrite' do
              expect(@times[Operators::PREVIOUS_YEAR][0][:replacer].call(
                       ConditionTreeLeaf.new('column', Operators::PREVIOUS_YEAR), 'Europe/Paris'
                     ))
                .to eq(ConditionTreeBranch.new('And', [
                                                 ConditionTreeLeaf.new('column', Operators::GREATER_THAN,
                                                                       times.format(Time.now.prev_year.beginning_of_year)),
                                                 ConditionTreeLeaf.new('column', Operators::LESS_THAN,
                                                                       times.format(Time.now.beginning_of_year))
                                               ]))
            end

            it 'Today should rewrite' do
              expect(@times[Operators::TODAY][0][:replacer].call(ConditionTreeLeaf.new('column', Operators::TODAY),
                                                                 'Europe/Paris'))
                .to eq(ConditionTreeBranch.new('And', [
                                                 ConditionTreeLeaf.new('column', Operators::GREATER_THAN,
                                                                       times.format(Time.now.beginning_of_day)),
                                                 ConditionTreeLeaf.new('column', Operators::LESS_THAN,
                                                                       times.format(Time.now.beginning_of_day + 1.day))
                                               ]))
            end

            it 'Yesterday should rewrite' do
              expect(@times[Operators::YESTERDAY][0][:replacer].call(
                       ConditionTreeLeaf.new('column', Operators::YESTERDAY), 'Europe/Paris'
                     ))
                .to eq(ConditionTreeBranch.new('And', [
                                                 ConditionTreeLeaf.new('column', Operators::GREATER_THAN,
                                                                       times.format(Time.now.yesterday.beginning_of_day)),
                                                 ConditionTreeLeaf.new('column', Operators::LESS_THAN,
                                                                       times.format(Time.now.beginning_of_day))
                                               ]))
            end
          end
        end
      end
    end
  end
end
