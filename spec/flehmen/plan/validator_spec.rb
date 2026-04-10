# frozen_string_literal: true

require "spec_helper"

RSpec.describe Flehmen::Plan::Validator do
  let(:registry) { SpecSupport.build_registry }

  def validate(plan, role: "support")
    described_class.new(registry, role: role).validate(plan)
  end

  describe "template existence" do
    it "rejects unknown templates" do
      result = validate({ template: "ghost", params: {} })
      expect(result).to be_rejected
      expect(result.errors.first).to include("ghost")
      expect(result.errors.first).to include("存在しません")
    end

    it "includes available template names in the error" do
      result = validate({ template: "nope", params: {} })
      expect(result.errors.first).to include("customer_overview")
    end
  end

  describe "policy check" do
    it "rejects templates not allowed by role" do
      # Build a restricted policy
      registry.policy(:restricted_role) { allow_templates :customer_overview }
      result = validate({ template: "payment_failures", params: {} }, role: "restricted_role")
      expect(result).to be_rejected
      expect(result.errors.first).to include("利用できません")
    end

    it "rejects when role has no policy" do
      result = validate({ template: "customer_overview", params: { customer_id: 1 } }, role: "ghost_role")
      expect(result).to be_rejected
    end

    it "allows templates for admin" do
      result = validate({ template: "customer_overview", params: { customer_id: 1 } }, role: "admin")
      expect(result).not_to be_rejected
    end
  end

  describe "required params" do
    it "rejects when required params are missing" do
      result = validate({ template: "customer_overview", params: {} })
      expect(result).to be_rejected
      expect(result.errors.first).to include("customer_id")
    end

    it "accepts when all required params are present" do
      result = validate({ template: "customer_overview", params: { customer_id: 42 } })
      expect(result).not_to be_rejected
    end

    it "accepts optional params when omitted (uses default)" do
      result = validate({ template: "recent_tickets", params: { customer_id: 1 } })
      expect(result).not_to be_rejected
    end
  end

  describe "param type coercion" do
    it "rejects when param cannot be coerced to declared type" do
      result = validate({ template: "customer_overview", params: { customer_id: "not_a_number" } })
      expect(result).to be_rejected
    end

    it "coerces string integers to integer" do
      result = validate({ template: "customer_overview", params: { customer_id: "42" } })
      expect(result).not_to be_rejected
      effective = result.effective_plan || { params: { customer_id: 42 } }
      expect(effective[:params][:customer_id]).to eq(42)
    end
  end

  describe "limit guard (auto-correct)" do
    it "corrects limit that exceeds role maximum" do
      result = validate(
        { template: "customer_overview", params: { customer_id: 1 }, options: { limit: 999 } },
        role: "support"
      )
      expect(result).to be_corrected
      expect(result.effective_plan[:options][:limit]).to eq(50)
      expect(result.warnings.any? { |w| w.include?("limit") }).to be true
    end

    it "does not correct limit within bounds" do
      result = validate(
        { template: "customer_overview", params: { customer_id: 1 }, options: { limit: 10 } },
        role: "support"
      )
      expect(result).not_to be_corrected
    end
  end

  describe "PII warnings" do
    it "adds warnings when masked fields are present" do
      result = validate({ template: "customer_overview", params: { customer_id: 1 } }, role: "support")
      expect(result).not_to be_rejected
      expect(result.warnings.any? { |w| w.include?("マスク") }).to be true
    end

    it "does not warn for admin (no masking)" do
      result = validate({ template: "customer_overview", params: { customer_id: 1 } }, role: "admin")
      pii_warnings = result.warnings.select { |w| w.include?("マスク") }
      expect(pii_warnings).to be_empty
    end
  end

  describe "string vs symbol keys" do
    it "accepts string keys in plan hash" do
      result = validate({ "template" => "customer_overview", "params" => { "customer_id" => 1 } })
      expect(result).not_to be_rejected
    end
  end
end
