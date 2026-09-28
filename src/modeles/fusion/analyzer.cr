# SPDX-License-Identifier: AGPL-3.0-or-later

module Modeles
  module Fusion
    # Remarque d'un contrôle : clé de traduction `modeles.check.<code>` et
    # paramètres.
    record Issue, code : String, params : Hash(String, String) = {} of String => String do
      def key : String
        "modeles.check.#{code}"
      end
    end

    # Rapport du contrôle d'un modèle (ADR-010 D3) : erreurs (le dépôt est
    # refusé), remarques, champs imprimés (`lignes.designation` pour
    # `{{ ligne.designation }}` dans une boucle sur `lignes`), champs lus
    # dans une condition et listes parcourues.
    class Report
      getter errors = [] of Issue
      getter warnings = [] of Issue
      getter printed = Set(String).new
      getter referenced = Set(String).new
      getter loops = Set(String).new

      def ok? : Bool
        errors.empty?
      end

      def error(code : String, params = {} of String => String) : Nil
        issue = Issue.new(code, params)
        @errors << issue unless @errors.includes?(issue)
      end

      def warning(code : String, params = {} of String => String) : Nil
        issue = Issue.new(code, params)
        @warnings << issue unless @warnings.includes?(issue)
      end
    end

    # Analyse statique d'un gabarit (ADR-010 D2, D3) : le moteur est celui
    # de Marten, bridé au seul contexte de fusion.
    #
    # * balises admises : `for`, `if`, `elsif`, `else`, `unless`, les
    #   fermetures et `verbatim` ; toute autre (`include`, `extend`, `url`,
    #   `translate`, `assign`…) est refusée ;
    # * filtres admis : `capitalize`, `default`, `downcase`, `upcase`,
    #   `join`, `size`, `truncate` (`safe` et `escape` défont l'échappement
    #   selon le format et sont refusés) ;
    # * champs : ceux de `Vocabulary`, les variables de boucle et `loop` ;
    # * mentions obligatoires selon le type de document (`Requirements`).
    module Analyzer
      extend Marten::Template::Tag::CanSplitSmartly

      ALLOWED_TAGS    = %w[for endfor if elsif else endif unless endunless verbatim endverbatim]
      ALLOWED_FILTERS = %w[capitalize default downcase upcase join size truncate]
      OPERATORS       = %w[|| && not in == != > >= < <=]
      LITERAL         = /\A(?:-?\d+(?:\.\d+)?|"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|true|false|nil)\z/

      # Variable de boucle : son nom et la liste parcourue (`nil` si ce
      # n'est pas une liste du vocabulaire).
      record Scope, variable : String, list : String?

      def self.analyze(source : String, kind : String? = nil) : Report
        report = Report.new
        tokens = begin
          Marten::Template::Parser::Lexer.new(source).tokenize
        rescue error
          report.error("syntax", {"message" => error.message.to_s})
          return report
        end

        scopes = [] of Scope
        verbatim = false
        tokens.each do |token|
          case token.type
          when .tag?
            name = token.content.split.first?
            verbatim = true if name == "verbatim"
            verbatim = false if name == "endverbatim"
            tag(token.content, scopes, report)
          when .variable? then expression(token.content, scopes, report, printed: true)
          when .text?     then unclosed(token.content, report) unless verbatim
          end
        end
        structure(source, report)
        Requirements.check(kind, report) if kind && report.ok?
        report
      end

      # Ouverture de balise sans fermeture sur la même ligne (`{{ facture.numero`).
      private def self.unclosed(text : String, report : Report) : Nil
        if match = text.match(/(\{\{|\{%)[^\n]{0,40}/)
          report.error("unclosed", {"excerpt" => match[0]})
        end
      end

      # Structure complète (balises fermées, filtres connus) : analyse du
      # moteur de Marten, sans rendu.
      private def self.structure(source : String, report : Report) : Nil
        Marten::Template::Template.new(source)
      rescue error : Marten::Template::Errors::InvalidSyntax
        report.error("syntax", {"message" => error.message.to_s})
      rescue error
        report.error("syntax", {"message" => error.message.to_s})
      end

      private def self.tag(content : String, scopes : Array(Scope), report : Report) : Nil
        parts = split_smartly(content)
        name = parts.first? || ""
        unless ALLOWED_TAGS.includes?(name)
          report.error("tag_forbidden", {"tag" => "{% #{content} %}"})
          return
        end
        case name
        when "for"
          if parts.size != 4 || parts[2] != "in" || !parts[1].matches?(/\A[a-z_][a-z0-9_]*\z/)
            report.error("for_syntax", {"tag" => "{% #{content} %}"})
            scopes << Scope.new("", nil)
          else
            list = expression(parts[3], scopes, report, printed: false, iterable: true)
            report.loops << list if list
            scopes << Scope.new(parts[1], list)
          end
        when "if", "unless", "elsif"
          condition(parts[1..], scopes, report, content)
        when "endfor"
          scopes.pop?
        end
      end

      private def self.condition(parts : Array(String), scopes : Array(Scope), report : Report, content : String) : Nil
        report.error("condition_empty", {"tag" => "{% #{content} %}"}) if parts.empty?
        parts.each do |part|
          next if OPERATORS.includes?(part)
          expression(part.lstrip('!'), scopes, report, printed: false)
        end
      end

      # Contrôle d'une expression `chemin|filtre:argument` ; rend le chemin
      # normalisé d'une liste du vocabulaire (`iterable`), sinon `nil`.
      private def self.expression(raw : String, scopes : Array(Scope), report : Report, printed : Bool,
                                  iterable : Bool = false) : String?
        parts = split_filters(raw.strip)
        head = parts.first.strip
        filters = parts[1..]
        filters.each do |filter|
          name, _, argument = filter.strip.partition(':')
          unless ALLOWED_FILTERS.includes?(name.strip)
            report.error("filter_forbidden", {"filter" => name.strip, "expression" => raw.strip})
          end
          argument = argument.strip
          path(argument, scopes, report, printed: false, filtered: true) unless argument.empty? || argument.matches?(LITERAL)
        end
        return if head.empty? || head.matches?(LITERAL)
        path(head, scopes, report, printed: printed, filtered: !filters.empty?, iterable: iterable)
      end

      # Découpe `a|b:"x|y"|c` sur les barres hors guillemets.
      private def self.split_filters(raw : String) : Array(String)
        parts = [] of String
        current = String::Builder.new
        quote = nil.as(Char?)
        raw.each_char do |char|
          if quote
            quote = nil if char == quote
            current << char
          elsif char.in?('"', '\'')
            quote = char
            current << char
          elsif char == '|'
            parts << current.to_s
            current = String::Builder.new
          else
            current << char
          end
        end
        parts << current.to_s
        parts
      end

      # Contrôle d'un chemin (`facture.numero`, `ligne.designation`,
      # `loop.index`) ; rend la liste du vocabulaire désignée, s'il y en a une.
      # ameba:disable Metrics/CyclomaticComplexity
      private def self.path(raw : String, scopes : Array(Scope), report : Report, printed : Bool,
                            filtered : Bool = false, iterable : Bool = false) : String?
        segments = raw.split('.')
        head = segments.first
        rest = segments[1..]
        unknown = -> { report.error("unknown_field", {"field" => raw}); nil.as(String?) }

        if head == "loop"
          return unknown.call if scopes.empty?
          return if rest.empty? || rest.all? { |segment| Vocabulary::LOOP.includes?(segment) }
          return unknown.call
        end

        if scope = scopes.reverse.find { |item| item.variable == head }
          list = scope.list
          return if list.nil?
          fields = Vocabulary::LISTS[list]
          if rest.empty?
            report.error("incomplete_field", {"field" => raw}) if printed && !filtered
            return
          end
          return unknown.call unless rest.size == 1 && fields.includes?(rest.first)
          record(report, "#{list}.#{rest.first}", printed)
          return
        end

        if fields = Vocabulary::OBJECTS[head]?
          if rest.empty?
            report.error("incomplete_field", {"field" => raw}) if printed && !filtered
            report.error("not_a_list", {"field" => raw}) if iterable
            return
          end
          return unknown.call unless rest.size == 1 && fields.includes?(rest.first)
          report.error("not_a_list", {"field" => raw}) if iterable
          record(report, "#{head}.#{rest.first}", printed)
          return
        end

        if fields = Vocabulary::LISTS[head]?
          if rest.empty?
            if printed && !filtered && !Vocabulary::PRINTABLE_LISTS.includes?(head)
              report.error("incomplete_field", {"field" => raw})
            end
            record(report, head, printed)
            return head
          end
          # Élément par son rang : `lignes.0.designation`.
          if rest.size == 2 && rest.first.matches?(/\A\d+\z/) && fields.includes?(rest.last)
            record(report, "#{head}.#{rest.last}", printed)
            return
          end
          return unknown.call
        end

        unknown.call
      end

      private def self.record(report : Report, normalized : String, printed : Bool) : Nil
        printed ? report.printed << normalized : report.referenced << normalized
      end
    end
  end
end
