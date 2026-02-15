module Shards
  module SPDX
    enum Category
      Permissive
      WeakCopyleft
      StrongCopyleft
      NonCommercial
      PublicDomain
      Proprietary
      Unknown
    end

    record LicenseInfo, id : String, name : String, osi_approved : Bool, category : Category

    LICENSES = {
      # Permissive licenses
      "MIT"              => LicenseInfo.new("MIT", "MIT License", true, Category::Permissive),
      "Apache-2.0"       => LicenseInfo.new("Apache-2.0", "Apache License 2.0", true, Category::Permissive),
      "BSD-2-Clause"     => LicenseInfo.new("BSD-2-Clause", "BSD 2-Clause \"Simplified\" License", true, Category::Permissive),
      "BSD-3-Clause"     => LicenseInfo.new("BSD-3-Clause", "BSD 3-Clause \"New\" or \"Revised\" License", true, Category::Permissive),
      "ISC"              => LicenseInfo.new("ISC", "ISC License", true, Category::Permissive),
      "Zlib"             => LicenseInfo.new("Zlib", "zlib License", true, Category::Permissive),
      "0BSD"             => LicenseInfo.new("0BSD", "BSD Zero Clause License", true, Category::Permissive),
      "WTFPL"            => LicenseInfo.new("WTFPL", "Do What The F*ck You Want To Public License", false, Category::Permissive),
      "CC-BY-4.0"        => LicenseInfo.new("CC-BY-4.0", "Creative Commons Attribution 4.0 International", false, Category::Permissive),
      "PostgreSQL"       => LicenseInfo.new("PostgreSQL", "PostgreSQL License", true, Category::Permissive),
      "BlueOak-1.0.0"    => LicenseInfo.new("BlueOak-1.0.0", "Blue Oak Model License 1.0.0", false, Category::Permissive),
      "Artistic-2.0"     => LicenseInfo.new("Artistic-2.0", "Artistic License 2.0", true, Category::Permissive),
      "BSL-1.0"          => LicenseInfo.new("BSL-1.0", "Boost Software License 1.0", true, Category::Permissive),
      "MS-PL"            => LicenseInfo.new("MS-PL", "Microsoft Public License", true, Category::Permissive),
      "ECL-2.0"          => LicenseInfo.new("ECL-2.0", "Educational Community License v2.0", true, Category::Permissive),
      "BSD-1-Clause"     => LicenseInfo.new("BSD-1-Clause", "BSD 1-Clause License", true, Category::Permissive),
      "AFL-3.0"          => LicenseInfo.new("AFL-3.0", "Academic Free License v3.0", true, Category::Permissive),
      "Python-2.0"       => LicenseInfo.new("Python-2.0", "Python License 2.0", true, Category::Permissive),
      "Ruby"             => LicenseInfo.new("Ruby", "Ruby License", false, Category::Permissive),
      "Unicode-DFS-2016" => LicenseInfo.new("Unicode-DFS-2016", "Unicode License Agreement - Data Files and Software (2016)", false, Category::Permissive),
      "Vim"              => LicenseInfo.new("Vim", "Vim License", false, Category::Permissive),
      "NCSA"             => LicenseInfo.new("NCSA", "University of Illinois/NCSA Open Source License", true, Category::Permissive),
      "X11"              => LicenseInfo.new("X11", "X11 License", false, Category::Permissive),
      "Libpng"           => LicenseInfo.new("Libpng", "libpng License", false, Category::Permissive),
      "curl"             => LicenseInfo.new("curl", "curl License", false, Category::Permissive),

      # Public domain licenses
      "Unlicense" => LicenseInfo.new("Unlicense", "The Unlicense", true, Category::PublicDomain),
      "CC0-1.0"   => LicenseInfo.new("CC0-1.0", "Creative Commons Zero v1.0 Universal", false, Category::PublicDomain),

      # Weak copyleft licenses
      "MPL-2.0"           => LicenseInfo.new("MPL-2.0", "Mozilla Public License 2.0", true, Category::WeakCopyleft),
      "LGPL-2.1-only"     => LicenseInfo.new("LGPL-2.1-only", "GNU Lesser General Public License v2.1 only", true, Category::WeakCopyleft),
      "LGPL-2.1-or-later" => LicenseInfo.new("LGPL-2.1-or-later", "GNU Lesser General Public License v2.1 or later", true, Category::WeakCopyleft),
      "LGPL-3.0-only"     => LicenseInfo.new("LGPL-3.0-only", "GNU Lesser General Public License v3.0 only", true, Category::WeakCopyleft),
      "LGPL-3.0-or-later" => LicenseInfo.new("LGPL-3.0-or-later", "GNU Lesser General Public License v3.0 or later", true, Category::WeakCopyleft),
      "EPL-2.0"           => LicenseInfo.new("EPL-2.0", "Eclipse Public License 2.0", true, Category::WeakCopyleft),
      "CC-BY-SA-4.0"      => LicenseInfo.new("CC-BY-SA-4.0", "Creative Commons Attribution Share Alike 4.0 International", false, Category::WeakCopyleft),
      "EUPL-1.2"          => LicenseInfo.new("EUPL-1.2", "European Union Public License 1.2", true, Category::WeakCopyleft),
      "MS-RL"             => LicenseInfo.new("MS-RL", "Microsoft Reciprocal License", true, Category::WeakCopyleft),
      "CDDL-1.0"          => LicenseInfo.new("CDDL-1.0", "Common Development and Distribution License 1.0", true, Category::WeakCopyleft),
      "CPAL-1.0"          => LicenseInfo.new("CPAL-1.0", "Common Public Attribution License 1.0", true, Category::WeakCopyleft),
      "EPL-1.0"           => LicenseInfo.new("EPL-1.0", "Eclipse Public License 1.0", true, Category::WeakCopyleft),
      "MulanPSL-2.0"      => LicenseInfo.new("MulanPSL-2.0", "Mulan Permissive Software License, Version 2", true, Category::WeakCopyleft),

      # Strong copyleft licenses
      "GPL-2.0-only"      => LicenseInfo.new("GPL-2.0-only", "GNU General Public License v2.0 only", true, Category::StrongCopyleft),
      "GPL-2.0-or-later"  => LicenseInfo.new("GPL-2.0-or-later", "GNU General Public License v2.0 or later", true, Category::StrongCopyleft),
      "GPL-3.0-only"      => LicenseInfo.new("GPL-3.0-only", "GNU General Public License v3.0 only", true, Category::StrongCopyleft),
      "GPL-3.0-or-later"  => LicenseInfo.new("GPL-3.0-or-later", "GNU General Public License v3.0 or later", true, Category::StrongCopyleft),
      "AGPL-3.0-only"     => LicenseInfo.new("AGPL-3.0-only", "GNU Affero General Public License v3.0", true, Category::StrongCopyleft),
      "AGPL-3.0-or-later" => LicenseInfo.new("AGPL-3.0-or-later", "GNU Affero General Public License v3.0 or later", true, Category::StrongCopyleft),
      "OSL-3.0"           => LicenseInfo.new("OSL-3.0", "Open Software License 3.0", true, Category::StrongCopyleft),

      # Non-commercial licenses
      "CC-BY-NC-4.0"    => LicenseInfo.new("CC-BY-NC-4.0", "Creative Commons Attribution NonCommercial 4.0 International", false, Category::NonCommercial),
      "CC-BY-NC-SA-4.0" => LicenseInfo.new("CC-BY-NC-SA-4.0", "Creative Commons Attribution NonCommercial ShareAlike 4.0 International", false, Category::NonCommercial),

      # Proprietary / source-available licenses
      "SSPL-1.0" => LicenseInfo.new("SSPL-1.0", "Server Side Public License, v 1", false, Category::Proprietary),
      "BSL-1.1"  => LicenseInfo.new("BSL-1.1", "Business Source License 1.1", false, Category::Proprietary),
    }

    # --- Expression AST ---

    abstract class Expression
      abstract def license_ids : Array(String)
      abstract def satisfied_by?(allowed : Set(String)) : Bool
    end

    class SimpleExpression < Expression
      getter id : String
      getter or_later : Bool

      def initialize(@id : String, @or_later : Bool = false)
      end

      def license_ids : Array(String)
        [id]
      end

      def satisfied_by?(allowed : Set(String)) : Bool
        allowed.includes?(id)
      end
    end

    class WithExpression < Expression
      getter license : SimpleExpression
      getter exception : String

      def initialize(@license : SimpleExpression, @exception : String)
      end

      def license_ids : Array(String)
        license.license_ids
      end

      def satisfied_by?(allowed : Set(String)) : Bool
        license.satisfied_by?(allowed)
      end
    end

    class AndExpression < Expression
      getter left : Expression
      getter right : Expression

      def initialize(@left : Expression, @right : Expression)
      end

      def license_ids : Array(String)
        left.license_ids + right.license_ids
      end

      def satisfied_by?(allowed : Set(String)) : Bool
        left.satisfied_by?(allowed) && right.satisfied_by?(allowed)
      end
    end

    class OrExpression < Expression
      getter left : Expression
      getter right : Expression

      def initialize(@left : Expression, @right : Expression)
      end

      def license_ids : Array(String)
        left.license_ids + right.license_ids
      end

      def satisfied_by?(allowed : Set(String)) : Bool
        left.satisfied_by?(allowed) || right.satisfied_by?(allowed)
      end
    end

    # --- Parser ---

    class Parser
      @tokens : Array(String)
      @pos : Int32

      def self.parse(input : String) : Expression
        new(input).parse
      end

      private def initialize(input : String)
        @tokens = tokenize(input)
        @pos = 0
      end

      def parse : Expression
        raise Error.new("Empty SPDX expression") if @tokens.empty?
        expr = parse_or
        unless @pos >= @tokens.size
          raise Error.new("Unexpected token '#{@tokens[@pos]}' at position #{@pos} in SPDX expression")
        end
        expr
      end

      private def tokenize(input : String) : Array(String)
        tokens = [] of String
        i = 0
        while i < input.size
          ch = input[i]
          case ch
          when ' ', '\t'
            i += 1
          when '('
            tokens << "("
            i += 1
          when ')'
            tokens << ")"
            i += 1
          else
            start = i
            while i < input.size && input[i] != ' ' && input[i] != '\t' && input[i] != '(' && input[i] != ')'
              i += 1
            end
            token = input[start...i]
            # Handle "+" suffix: split "GPL-3.0+" into "GPL-3.0" and "+"
            if token.ends_with?("+") && token.size > 1 && token != "+"
              tokens << token[0...-1]
              tokens << "+"
            else
              tokens << token
            end
          end
        end
        tokens
      end

      private def peek : String?
        return nil if @pos >= @tokens.size
        @tokens[@pos]
      end

      private def advance : String
        token = @tokens[@pos]
        @pos += 1
        token
      end

      private def expect(value : String) : String
        token = peek
        unless token == value
          raise Error.new("Expected '#{value}' but got '#{token || "end of input"}' in SPDX expression")
        end
        advance
      end

      # or-expression = and-expression ("OR" and-expression)*
      private def parse_or : Expression
        left = parse_and
        while peek == "OR"
          advance # consume "OR"
          right = parse_and
          left = OrExpression.new(left, right)
        end
        left
      end

      # and-expression = atom ("AND" atom)*
      private def parse_and : Expression
        left = parse_atom
        while peek == "AND"
          advance # consume "AND"
          right = parse_atom
          left = AndExpression.new(left, right)
        end
        left
      end

      # atom = "(" expression ")"
      #      | simple-expression ["WITH" exception-id]
      private def parse_atom : Expression
        token = peek
        raise Error.new("Unexpected end of SPDX expression") if token.nil?

        if token == "("
          advance # consume "("
          expr = parse_or
          expect(")")
          return expr
        end

        # simple-expression: license-id ["+" ]
        license_id = advance
        if license_id == "AND" || license_id == "OR" || license_id == "WITH" || license_id == "+" || license_id == "(" || license_id == ")"
          raise Error.new("Unexpected token '#{license_id}' in SPDX expression where license ID was expected")
        end

        or_later = false
        if peek == "+"
          advance # consume "+"
          or_later = true
        end

        simple = SimpleExpression.new(license_id, or_later)

        # Check for "WITH" exception
        if peek == "WITH"
          advance # consume "WITH"
          exception_id = peek
          raise Error.new("Expected exception ID after 'WITH' in SPDX expression") if exception_id.nil?
          advance
          return WithExpression.new(simple, exception_id)
        end

        simple
      end
    end

    # --- Module-level methods ---

    def self.valid_id?(id : String) : Bool
      LICENSES.has_key?(id) || id.starts_with?("LicenseRef-")
    end

    def self.lookup(id : String) : LicenseInfo?
      LICENSES[id]?
    end

    def self.category_for(id : String) : Category
      LICENSES[id]?.try(&.category) || Category::Unknown
    end

    def self.parse(expression : String) : Expression
      Parser.parse(expression)
    end
  end
end
