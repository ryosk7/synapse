# frozen_string_literal: true

module Flehmen
  module Execution
    # Executes a compiled ActiveRecord::Relation in a read-only context.
    #
    # read-only は 2 段階で担保する:
    #   1. ActiveRecord::Base.while_preventing_writes — write 操作を例外で弾く
    #   2. Configuration#read_only_connection が false の場合も while_preventing_writes は実行される
    #      (将来的に connected_to(role: :reading) で replica に誘導する拡張を想定)
    class Runner
      # @param scope [ActiveRecord::Relation]
      # @return [Array<ActiveRecord::Base>]
      def execute(scope)
        ActiveRecord::Base.while_preventing_writes do
          scope.to_a
        end
      rescue ActiveRecord::ReadOnlyError => e
        raise Flehmen::ReadOnlyViolationError,
              "Read-only violation detected: #{e.message}"
      end
    end
  end
end
