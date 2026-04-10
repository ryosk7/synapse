# frozen_string_literal: true

require "active_record"
require "active_support"
require "active_support/core_ext/integer/time"
require "flehmen"

# ── In-memory SQLite setup ──────────────────────────────────────────────────
ActiveRecord::Base.establish_connection(
  adapter:  "sqlite3",
  database: ":memory:"
)

ActiveRecord::Schema.define do
  create_table :customers, force: true do |t|
    t.string  :name
    t.string  :email
    t.string  :phone
    t.string  :status,    default: "active"
    t.string  :plan_name
    t.string  :stripe_id
    t.timestamps null: true
  end

  create_table :support_tickets, force: true do |t|
    t.integer :customer_id
    t.string  :subject
    t.string  :status,   default: "open"
    t.string  :priority, default: "normal"
    t.timestamps null: true
  end

  create_table :orders, force: true do |t|
    t.integer :customer_id
    t.decimal :amount, precision: 10, scale: 2
    t.string  :status
    t.datetime :failed_at
    t.timestamps null: true
  end
end

# ── Test models ─────────────────────────────────────────────────────────────
class Customer < ActiveRecord::Base
  has_many :support_tickets
  has_many :orders
end

class SupportTicket < ActiveRecord::Base
  belongs_to :customer
end

class Order < ActiveRecord::Base
  belongs_to :customer
end

# ── Shared catalog fixture ───────────────────────────────────────────────────
module SpecSupport
  def self.build_registry
    registry = Flehmen::Catalog::Registry.new

    registry.resource(:Customer, model: "Customer") do
      field :id,         classification: :public
      field :name,       classification: :personal, mask: :name
      field :email,      classification: :personal, mask: :email
      field :phone,      classification: :personal, mask: :phone
      field :status,     classification: :public
      field :plan_name,  classification: :internal
      field :stripe_id,  classification: :sensitive
      field :created_at, classification: :public
    end

    registry.resource(:SupportTicket, model: "SupportTicket") do
      field :id,          classification: :public
      field :customer_id, classification: :public
      field :subject,     classification: :internal
      field :status,      classification: :public
      field :priority,    classification: :public
      field :created_at,  classification: :public
    end

    registry.resource(:Order, model: "Order") do
      field :id,          classification: :public
      field :customer_id, classification: :public
      field :amount,      classification: :internal
      field :status,      classification: :public
      field :failed_at,   classification: :public
      field :created_at,  classification: :public
    end

    registry.template(:customer_overview) do
      description "顧客の基本情報を表示"
      resource :Customer
      fields [:id, :name, :email, :phone, :status, :plan_name, :created_at]
      param :customer_id, type: :integer, required: true, description: "顧客ID"
      filter :by_id, field: :id, operator: :eq, param: :customer_id
    end

    registry.template(:recent_tickets) do
      description "顧客の直近の問い合わせ一覧"
      resource :SupportTicket
      fields [:id, :customer_id, :subject, :status, :priority, :created_at]
      param :customer_id, type: :integer, required: true
      param :days_ago,    type: :integer, required: false, default: 30
      filter :by_customer, field: :customer_id, operator: :eq, param: :customer_id
      filter :recent, field: :created_at, operator: :gte, param: :days_ago,
             transform: ->(days) { days.to_i.days.ago }
      default_order :created_at, :desc
    end

    registry.template(:payment_failures) do
      description "直近の決済失敗を検索"
      resource :Order
      fields [:id, :customer_id, :amount, :status, :failed_at]
      param :days_ago, type: :integer, required: false, default: 30
      filter :failed, field: :status, operator: :eq, value: "failed"
      filter :recent, field: :created_at, operator: :gte, param: :days_ago,
             transform: ->(days) { days.to_i.days.ago }
      default_order :failed_at, :desc
    end

    registry.policy(:support) do
      allow_templates :customer_overview, :recent_tickets, :payment_failures
      max_results 50
    end

    registry.policy(:admin) do
      allow_all_templates
      max_results 100
    end

    registry
  end
end

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.order = :random

  # Reset Flehmen catalog between tests
  config.before(:each) do
    Flehmen.reset_catalog!
    Flehmen.reset_configuration!
  end

  # Clean DB between integration tests
  config.before(:each, :db) do
    [Customer, SupportTicket, Order].each(&:delete_all)
  end
end
