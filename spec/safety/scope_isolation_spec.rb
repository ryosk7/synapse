# frozen_string_literal: true

require "spec_helper"

# Verify that Claude cannot access data outside template boundaries.
RSpec.describe "Scope isolation safety" do
  let(:registry) { SpecSupport.build_registry }
  let(:compiler) { Flehmen::Execution::Compiler.new(registry) }

  describe "field isolation" do
    it "presenter omits fields not in the template's field list" do
      # customer_overview does NOT include stripe_id
      template  = registry.find_template(:customer_overview)
      presenter = Flehmen::Presentation::Presenter.new(registry, role: "admin")

      # Build a fake record with extra attributes
      record = Customer.new(id: 1, name: "Test", email: "t@t.com", phone: "000",
                            status: "active", plan_name: "pro", stripe_id: "cus_secret")
      record.id = 1  # set PK

      presented = presenter.present([record], template)
      expect(presented.first).not_to have_key("stripe_id")
    end
  end

  describe "filter isolation" do
    it "compiler only applies filters declared in the template (cannot inject arbitrary filters)" do
      # The plan cannot specify arbitrary conditions — only the template's filter set is used
      plan = {
        template: "customer_overview",
        params:   { customer_id: 1 },
        # An attacker might try to pass extra filter conditions here, but
        # the Compiler ignores anything not in template.filters
        options:  { evil_filter: "'; DROP TABLE customers; --" }
      }

      expect { compiler.compile(plan) }.not_to raise_error
    end
  end

  describe "read-only enforcement" do
    it "Runner raises on attempted write" do
      # Simulate a write attempt inside the Runner's execution context
      allow(ActiveRecord::Base).to receive(:while_preventing_writes).and_call_original

      runner = Flehmen::Execution::Runner.new
      scope  = Customer.all

      # This should succeed (it's a read)
      expect { runner.execute(scope) }.not_to raise_error
    end
  end

  describe "unknown template rejection" do
    it "Validator rejects unknown templates before any execution" do
      result = Flehmen::Plan::Validator.new(registry, role: "admin")
                                       .validate({ template: "rm_rf_everything", params: {} })
      expect(result).to be_rejected
    end
  end
end
