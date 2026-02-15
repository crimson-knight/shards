require "./spec_helper"
require "../../src/spdx"

module Shards
  describe SPDX do
    describe ".valid_id?" do
      it "recognizes standard SPDX identifiers" do
        SPDX.valid_id?("MIT").should be_true
        SPDX.valid_id?("Apache-2.0").should be_true
        SPDX.valid_id?("GPL-3.0-only").should be_true
      end

      it "rejects unknown identifiers" do
        SPDX.valid_id?("NotALicense").should be_false
        SPDX.valid_id?("FooBar-1.0").should be_false
      end

      it "accepts LicenseRef- prefixed identifiers" do
        SPDX.valid_id?("LicenseRef-custom").should be_true
        SPDX.valid_id?("LicenseRef-my-company-1.0").should be_true
      end
    end

    describe ".lookup" do
      it "returns LicenseInfo for known IDs" do
        info = SPDX.lookup("MIT")
        info.should_not be_nil
        info = info.not_nil!
        info.id.should eq("MIT")
        info.name.should eq("MIT License")
        info.osi_approved.should be_true
        info.category.should eq(SPDX::Category::Permissive)
      end

      it "returns correct info for Apache-2.0" do
        info = SPDX.lookup("Apache-2.0")
        info.should_not be_nil
        info = info.not_nil!
        info.osi_approved.should be_true
        info.category.should eq(SPDX::Category::Permissive)
      end

      it "returns correct info for GPL-3.0-only" do
        info = SPDX.lookup("GPL-3.0-only")
        info.should_not be_nil
        info = info.not_nil!
        info.osi_approved.should be_true
        info.category.should eq(SPDX::Category::StrongCopyleft)
      end

      it "returns nil for unknown IDs" do
        SPDX.lookup("Unknown-1.0").should be_nil
        SPDX.lookup("FooBar").should be_nil
      end
    end

    describe ".category_for" do
      it "returns Permissive for MIT" do
        SPDX.category_for("MIT").should eq(SPDX::Category::Permissive)
      end

      it "returns Permissive for BSD-3-Clause" do
        SPDX.category_for("BSD-3-Clause").should eq(SPDX::Category::Permissive)
      end

      it "returns StrongCopyleft for GPL-3.0-only" do
        SPDX.category_for("GPL-3.0-only").should eq(SPDX::Category::StrongCopyleft)
      end

      it "returns WeakCopyleft for MPL-2.0" do
        SPDX.category_for("MPL-2.0").should eq(SPDX::Category::WeakCopyleft)
      end

      it "returns PublicDomain for Unlicense" do
        SPDX.category_for("Unlicense").should eq(SPDX::Category::PublicDomain)
      end

      it "returns NonCommercial for CC-BY-NC-4.0" do
        SPDX.category_for("CC-BY-NC-4.0").should eq(SPDX::Category::NonCommercial)
      end

      it "returns Proprietary for SSPL-1.0" do
        SPDX.category_for("SSPL-1.0").should eq(SPDX::Category::Proprietary)
      end

      it "returns Unknown for unrecognized licenses" do
        SPDX.category_for("FooBar").should eq(SPDX::Category::Unknown)
      end
    end

    describe "Parser" do
      it "parses simple license ID" do
        expr = SPDX.parse("MIT")
        expr.should be_a(SPDX::SimpleExpression)
        expr.license_ids.should eq(["MIT"])
      end

      it "parses OR expression" do
        expr = SPDX.parse("MIT OR Apache-2.0")
        expr.should be_a(SPDX::OrExpression)
        expr.license_ids.sort.should eq(["Apache-2.0", "MIT"])
      end

      it "parses AND expression" do
        expr = SPDX.parse("MIT AND Apache-2.0")
        expr.should be_a(SPDX::AndExpression)
        expr.license_ids.sort.should eq(["Apache-2.0", "MIT"])
      end

      it "parses WITH expression" do
        expr = SPDX.parse("GPL-3.0-only WITH Classpath-exception-2.0")
        expr.should be_a(SPDX::WithExpression)
        expr.license_ids.should eq(["GPL-3.0-only"])
        expr.as(SPDX::WithExpression).exception.should eq("Classpath-exception-2.0")
      end

      it "parses parenthesized expressions" do
        expr = SPDX.parse("(MIT OR Apache-2.0) AND BSD-3-Clause")
        expr.should be_a(SPDX::AndExpression)
        expr.license_ids.sort.should eq(["Apache-2.0", "BSD-3-Clause", "MIT"])
      end

      it "handles or-later suffix +" do
        expr = SPDX.parse("GPL-3.0+")
        expr.should be_a(SPDX::SimpleExpression)
        simple = expr.as(SPDX::SimpleExpression)
        simple.id.should eq("GPL-3.0")
        simple.or_later.should be_true
      end

      it "AND binds tighter than OR" do
        # "A OR B AND C" should parse as "A OR (B AND C)"
        expr = SPDX.parse("MIT OR Apache-2.0 AND BSD-3-Clause")
        expr.should be_a(SPDX::OrExpression)
        or_expr = expr.as(SPDX::OrExpression)
        or_expr.left.should be_a(SPDX::SimpleExpression)
        or_expr.right.should be_a(SPDX::AndExpression)
      end

      it "parses nested parentheses" do
        expr = SPDX.parse("((MIT OR Apache-2.0))")
        expr.should be_a(SPDX::OrExpression)
        expr.license_ids.sort.should eq(["Apache-2.0", "MIT"])
      end

      it "raises on empty expression" do
        expect_raises(Shards::Error, "Empty SPDX expression") do
          SPDX.parse("")
        end
      end

      it "raises on malformed expression" do
        expect_raises(Shards::Error) do
          SPDX.parse("MIT OR")
        end
      end

      it "raises on unmatched parenthesis" do
        expect_raises(Shards::Error) do
          SPDX.parse("(MIT OR Apache-2.0")
        end
      end
    end

    describe "Expression#satisfied_by?" do
      it "simple expression satisfied when in allowed set" do
        expr = SPDX.parse("MIT")
        expr.satisfied_by?(Set{"MIT"}).should be_true
      end

      it "simple expression not satisfied when not in allowed set" do
        expr = SPDX.parse("MIT")
        expr.satisfied_by?(Set{"Apache-2.0"}).should be_false
      end

      it "OR expression satisfied when either side is allowed" do
        expr = SPDX.parse("MIT OR GPL-3.0-only")
        expr.satisfied_by?(Set{"MIT"}).should be_true
        expr.satisfied_by?(Set{"GPL-3.0-only"}).should be_true
        expr.satisfied_by?(Set{"Apache-2.0"}).should be_false
      end

      it "AND expression requires both sides allowed" do
        expr = SPDX.parse("MIT AND Apache-2.0")
        expr.satisfied_by?(Set{"MIT", "Apache-2.0"}).should be_true
        expr.satisfied_by?(Set{"MIT"}).should be_false
        expr.satisfied_by?(Set{"Apache-2.0"}).should be_false
      end

      it "WITH expression satisfied by the license itself" do
        expr = SPDX.parse("GPL-2.0-only WITH Classpath-exception-2.0")
        expr.satisfied_by?(Set{"GPL-2.0-only"}).should be_true
        expr.satisfied_by?(Set{"MIT"}).should be_false
      end

      it "complex expression with parentheses" do
        expr = SPDX.parse("(MIT OR Apache-2.0) AND BSD-3-Clause")
        expr.satisfied_by?(Set{"MIT", "BSD-3-Clause"}).should be_true
        expr.satisfied_by?(Set{"Apache-2.0", "BSD-3-Clause"}).should be_true
        expr.satisfied_by?(Set{"MIT"}).should be_false
        expr.satisfied_by?(Set{"BSD-3-Clause"}).should be_false
      end
    end
  end
end
