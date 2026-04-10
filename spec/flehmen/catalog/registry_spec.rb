# frozen_string_literal: true

require "spec_helper"

RSpec.describe Flehmen::Catalog::Registry do
  let(:registry) { SpecSupport.build_registry }

  describe "#find_template" do
    it "returns the template definition by name" do
      tmpl = registry.find_template(:customer_overview)
      expect(tmpl).to be_a(Flehmen::Catalog::TemplateDefinition)
      expect(tmpl.name).to eq(:customer_overview)
    end

    it "returns nil for unknown templates" do
      expect(registry.find_template(:nonexistent)).to be_nil
    end

    it "accepts string keys" do
      expect(registry.find_template("customer_overview")).not_to be_nil
    end
  end

  describe "#find_resource" do
    it "returns the resource definition by name" do
      res = registry.find_resource(:Customer)
      expect(res).to be_a(Flehmen::Catalog::ResourceDefinition)
      expect(res.model_name).to eq("Customer")
    end

    it "returns nil for unknown resources" do
      expect(registry.find_resource(:Unknown)).to be_nil
    end
  end

  describe "#find_policy" do
    it "returns the policy definition for a role" do
      policy = registry.find_policy(:support)
      expect(policy).to be_a(Flehmen::Catalog::PolicyDefinition)
      expect(policy.role).to eq(:support)
    end

    it "returns nil for unknown roles" do
      expect(registry.find_policy(:stranger)).to be_nil
    end
  end

  describe "#templates_for_role" do
    it "returns only templates allowed by the role policy" do
      templates = registry.templates_for_role("support")
      names = templates.map(&:name)
      expect(names).to include(:customer_overview, :recent_tickets, :payment_failures)
    end

    it "returns all templates for admin" do
      templates = registry.templates_for_role(:admin)
      expect(templates.size).to eq(registry.all_templates.size)
    end

    it "returns empty array for unknown role" do
      expect(registry.templates_for_role("ghost")).to be_empty
    end
  end

  describe "#all_templates" do
    it "returns all registered templates" do
      expect(registry.all_templates.size).to eq(3)
    end
  end

  describe "#template_names" do
    it "returns symbol keys" do
      expect(registry.template_names).to include(:customer_overview, :recent_tickets, :payment_failures)
    end
  end

  describe "#to_catalog_hash" do
    it "includes templates and resources" do
      h = registry.to_catalog_hash
      expect(h).to have_key(:templates)
      expect(h).to have_key(:resources)
    end

    it "filters templates by role when role is given" do
      h = registry.to_catalog_hash(role: :support)
      names = h[:templates].map { |t| t[:name] }
      expect(names).to include("customer_overview")
    end
  end

  describe "template fields" do
    it "has required params defined" do
      tmpl = registry.find_template(:customer_overview)
      expect(tmpl.required_params.map(&:name)).to include(:customer_id)
    end

    it "has filters defined" do
      tmpl = registry.find_template(:customer_overview)
      expect(tmpl.filters).to have_key(:by_id)
    end

    it "has default ordering" do
      tmpl = registry.find_template(:recent_tickets)
      expect(tmpl.default_order_field).to eq("created_at")
      expect(tmpl.default_order_dir).to eq(:desc)
    end
  end
end
