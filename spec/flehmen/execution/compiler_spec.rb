# frozen_string_literal: true

require "spec_helper"

RSpec.describe Flehmen::Execution::Compiler do
  let(:registry) { SpecSupport.build_registry }
  let(:compiler) { described_class.new(registry) }

  def compile(template, params, options = {})
    compiler.compile({ template: template.to_s, params: params, options: options })
  end

  describe "#compile" do
    it "returns an ActiveRecord::Relation" do
      scope = compile(:customer_overview, { customer_id: 1 })
      expect(scope).to be_a(ActiveRecord::Relation)
    end

    it "applies eq filter from params" do
      scope = compile(:customer_overview, { customer_id: 42 })
      sql = scope.to_sql
      expect(sql).to include("42")
      expect(sql).to match(/id.*=.*42|42.*id/i)
    end

    it "applies static filter (payment_failures uses status = 'failed')" do
      scope = compile(:payment_failures, { days_ago: 30 })
      sql = scope.to_sql
      expect(sql).to include("failed")
    end

    it "applies default ordering" do
      scope = compile(:recent_tickets, { customer_id: 1 })
      sql = scope.to_sql
      expect(sql).to match(/ORDER BY/i)
      expect(sql).to include("created_at")
    end

    it "applies custom ordering from options" do
      scope = compile(:customer_overview, { customer_id: 1 }, { order_by: "status", order_dir: "asc" })
      sql = scope.to_sql
      expect(sql).to include("status")
    end

    it "applies limit" do
      scope = compile(:customer_overview, { customer_id: 1 }, { limit: 5 })
      sql = scope.to_sql
      expect(sql).to match(/LIMIT\s+5/i)
    end

    it "caps limit at max_results when not specified" do
      scope = compile(:customer_overview, { customer_id: 1 })
      sql = scope.to_sql
      expect(sql).to match(/LIMIT\s+\d+/i)
    end

    it "raises ArgumentError for unknown template" do
      expect { compiler.compile({ template: "ghost", params: {} }) }
        .to raise_error(ArgumentError, /Template not found/)
    end

    it "raises ArgumentError when filter references non-existent column" do
      # Build a broken registry with a filter pointing to a ghost column
      bad_registry = Flehmen::Catalog::Registry.new
      bad_registry.resource(:Customer, model: "Customer") do
        field :id, classification: :public
      end
      bad_registry.template(:broken) do
        resource :Customer
        fields [:id]
        param :x, type: :integer, required: true
        filter :bad_col, field: :nonexistent_column, operator: :eq, param: :x
      end

      # Compiler validates columns eagerly during compile (not deferred to to_a)
      expect do
        Flehmen::Execution::Compiler.new(bad_registry)
          .compile({ template: "broken", params: { x: 1 } })
      end.to raise_error(ArgumentError, /nonexistent_column/)
    end
  end
end
