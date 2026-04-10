# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Full query flow", :db do
  let(:registry) { SpecSupport.build_registry }

  before do
    Customer.create!(id: 1, name: "田中太郎", email: "taro@example.com",
                     phone: "09012345678", status: "active", plan_name: "pro")
    Customer.create!(id: 2, name: "鈴木花子", email: "hanako@example.com",
                     phone: "08011112222", status: "churned", plan_name: "free")
    SupportTicket.create!(customer_id: 1, subject: "ログインできません", status: "open",  priority: "high")
    SupportTicket.create!(customer_id: 1, subject: "請求の確認",         status: "closed", priority: "normal")
  end

  def run_plan(plan, role: "support")
    validator = Flehmen::Plan::Validator.new(registry, role: role)
    result    = validator.validate(plan)
    raise "Plan rejected: #{result.errors.inspect}" if result.rejected?

    effective = result.effective_plan || plan
    scope     = Flehmen::Execution::Compiler.new(registry).compile(effective)
    records   = Flehmen::Execution::Runner.new.execute(scope)
    template  = registry.find_template(effective[:template])
    Flehmen::Presentation::Presenter.new(registry, role: role).present(records, template)
  end

  describe "customer_overview" do
    it "returns masked customer data for support role" do
      presented = run_plan({ template: "customer_overview", params: { customer_id: 1 } }, role: "support")
      expect(presented.size).to eq(1)
      record = presented.first
      expect(record["id"]).to eq(1)
      # name should be masked
      expect(record["name"]).to match(/田\*+/)
      # email should be masked
      expect(record["email"]).to match(/\*\*\*@example\.com/)
      # status is public
      expect(record["status"]).to eq("active")
      # stripe_id is not in template fields → should not appear
      expect(record).not_to have_key("stripe_id")
    end

    it "returns unmasked data for admin role" do
      presented = run_plan({ template: "customer_overview", params: { customer_id: 1 } }, role: "admin")
      expect(presented.first["name"]).to eq("田中太郎")
      expect(presented.first["email"]).to eq("taro@example.com")
    end

    it "only returns fields declared in the template (not all columns)" do
      presented = run_plan({ template: "customer_overview", params: { customer_id: 1 } }, role: "admin")
      allowed   = %w[id name email phone status plan_name created_at]
      presented.first.each_key do |key|
        expect(allowed).to include(key), "unexpected field: #{key}"
      end
    end
  end

  describe "recent_tickets" do
    it "returns tickets for a customer" do
      presented = run_plan({ template: "recent_tickets", params: { customer_id: 1 } }, role: "support")
      expect(presented.size).to eq(2)
    end

    it "does not return tickets for other customers" do
      presented = run_plan({ template: "recent_tickets", params: { customer_id: 2 } }, role: "support")
      expect(presented).to be_empty
    end
  end

  describe "validation → compile → execute pipeline" do
    it "rejects missing required param" do
      validator = Flehmen::Plan::Validator.new(registry, role: "support")
      result    = validator.validate({ template: "customer_overview", params: {} })
      expect(result).to be_rejected
    end

    it "corrects an over-limit" do
      validator = Flehmen::Plan::Validator.new(registry, role: "support")
      result    = validator.validate({
        template: "customer_overview",
        params:   { customer_id: 1 },
        options:  { limit: 999 }
      })
      expect(result).to be_corrected
      expect(result.effective_plan[:options][:limit]).to eq(50)
    end
  end
end
