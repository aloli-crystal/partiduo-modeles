# SPDX-License-Identifier: AGPL-3.0-or-later

module Modeles
  module Office
    # Préparation d'une partie XML d'un ODT ou d'un DOCX avant la fusion
    # (ADR-010 D2).
    #
    # . *Champs réunis.* Un traitement de texte coupe volontiers un champ
    #   `{{ facture.numero }}` en plusieurs fragments de mise en forme
    #   (`<w:r>` en DOCX, `<text:span>` en ODT : correcteur d'orthographe,
    #   gras sur une partie, révisions). Dans chaque paragraphe, chaque balise
    #   de fusion est ramenée entière dans le premier fragment qui la
    #   contient, les suivants perdent la partie reprise ; la mise en forme
    #   du premier caractère est gardée. Les entités XML de la balise sont
    #   décodées et les guillemets typographiques redressés (`“x”` → `"x"`).
    # . *Lignes de tableau répétées.* Une ligne de tableau (`<w:tr>`,
    #   `<table:table-row>`) qui contient `{% for … %}` est répétée quand le
    #   `{% endfor %}` qui lui répond est dans une autre cellule de la même
    #   ligne ou dans une ligne suivante : la balise est sortie avant la
    #   ligne, et le `{% endfor %}` après la ligne qui le contient. De même,
    #   un `{% if %}` (sans `else`) ouvert dans une ligne et fermé dans une
    #   autre cellule ou une ligne suivante rend ces lignes conditionnelles.
    #   Ouverture et fermeture dans la même cellule : le bloc reste dans le
    #   texte de la cellule.
    # . *Paragraphes de balises.* Un paragraphe du corps (hors tableau) qui
    #   ne contient que des balises de bloc (`{% if %}`, `{% for %}`,
    #   `{% endif %}`…) est remplacé par ces balises : il ne laisse pas de
    #   paragraphe vide dans le document rendu.
    class Normalizer
      TOKEN_RE = /<[^>]*>|[^<]+/
      SPAN_RE  = /\{\{.*?\}\}|\{%.*?%\}|\{#.*?#\}/m
      BLOCK_RE = /\{%.*?%\}/m
      # Paragraphe fait seulement de balises de bloc et de commentaires.
      TAGS_ONLY_RE = /\A\s*(?:(?:\{%.*?%\}|\{#.*?#\})\s*)+\z/m

      QUOTES = {'“' => '"', '”' => '"', '„' => '"', '«' => '"', '»' => '"', '‘' => '\'', '’' => '\'',
                '\u{00A0}' => ' ', '\u{202F}' => ' '}

      # Fragment de texte d'un paragraphe : jeton de l'archive, texte décodé,
      # `spaces` pour un élément d'espaces (`<text:s/>`).
      record Piece, token : Int32, text : String, spaces : Bool = false

      # Balise de bloc trouvée dans le texte : jeton, position, texte, nom,
      # et éléments qui l'entourent (ouverture du paragraphe, de la ligne).
      record Hit, token : Int32, offset : Int32, text : String, name : String, paragraph : Int32?, row : Int32?

      getter problems = [] of Fusion::Issue

      @tokens : Array(String)

      def initialize(xml : String, @flavor : Flavor)
        @tokens = xml.scan(TOKEN_RE).map(&.[0])
      end

      def self.normalize(xml : String, flavor : Flavor) : {String, Array(Fusion::Issue)}
        normalizer = new(xml, flavor)
        {normalizer.run, normalizer.problems}
      end

      def run : String
        join_fields
        hoist
        xml = @tokens.join
        @flavor.format == "docx" ? xml.gsub("<w:t>", %(<w:t xml:space="preserve">)) : xml
      end

      # --- Champs coupés -----------------------------------------------------------

      private def join_fields : Nil
        paragraphs = [] of Array(Piece)
        stack = [] of String
        @tokens.each_with_index do |token, index|
          if !token.starts_with?("<")
            text_piece(index, token, paragraphs.last?, stack)
          elsif !markup?(token)
            element(token, index, paragraphs, stack)
          end
        end
      end

      # Déclaration, commentaire ou instruction (`<?…?>`, `<!…>`).
      private def markup?(token : String) : Bool
        token.starts_with?("<?") || token.starts_with?("<!")
      end

      private def text_piece(index : Int32, token : String, pieces : Array(Piece)?, stack : Array(String)) : Nil
        return unless pieces
        text_element = @flavor.text_element
        pieces << Piece.new(index, HTML.unescape(token)) if text_element.nil? || stack.last? == text_element
      end

      private def element(token : String, index : Int32, paragraphs : Array(Array(Piece)), stack : Array(String)) : Nil
        name = @flavor.element_name(token)
        if token.starts_with?("</")
          stack.pop?
          paragraphs.pop?.try { |pieces| join(pieces) } if @flavor.paragraph?(name)
        elsif token.ends_with?("/>")
          count = @flavor.spaces(token)
          pieces = paragraphs.last?
          pieces << Piece.new(index, " " * count, spaces: true) if count && pieces
        else
          stack << name
          paragraphs << [] of Piece if @flavor.paragraph?(name)
        end
      end

      # Réunit les balises de fusion d'un paragraphe dans leur premier
      # fragment.
      private def join(pieces : Array(Piece)) : Nil
        text = pieces.join(&.text)
        spans = text.scan(SPAN_RE).map { |match| {match.begin, match.end} }
        return if spans.empty?

        owners = [] of Int32
        pieces.each_with_index { |piece, index| piece.text.size.times { owners << index } }
        rebuilt = Array(String::Builder).new(pieces.size) { String::Builder.new }
        emptied = Set(Int32).new
        position = 0
        span_index = 0
        while position < text.size
          span = spans[span_index]?
          if span && position == span[0]
            owner = owners[position]
            (span[0]...span[1]).each { |inside| emptied << owners[inside] if owners[inside] != owner }
            rebuilt[owner] << straighten(text[span[0]...span[1]])
            position = span[1]
            span_index += 1
          else
            rebuilt[owners[position]] << escape(text[position])
            position += 1
          end
        end
        pieces.each_with_index do |piece, index|
          content = rebuilt[index].to_s
          if piece.spaces
            @tokens[piece.token] = "" if emptied.includes?(index) && content.empty?
          else
            @tokens[piece.token] = content
          end
        end
      end

      private def straighten(tag : String) : String
        tag.gsub { |char| QUOTES[char]? || char }
      end

      private def escape(char : Char) : String
        case char
        when '&' then "&amp;"
        when '<' then "&lt;"
        when '>' then "&gt;"
        else          char.to_s
        end
      end

      # --- Lignes de tableau et paragraphes de balises -----------------------------

      # Éléments ouverts (ouverture → fermeture) et parent de chaque
      # paragraphe, relevés par `scan_blocks`, et modifications à appliquer.
      @closes = {} of Int32 => Int32
      @parents = {} of Int32 => String?
      @hits = [] of Hit
      @removals = Hash(Int32, Array(Hit)).new { |hash, key| hash[key] = [] of Hit }
      @before = Hash(Int32, String).new("")
      @after = Hash(Int32, String).new("")
      @hoisted = Set(Hit).new
      @replaced = {} of Int32 => String

      private def hoist : Nil
        scan_blocks
        hoist_rows
        hoist_paragraphs
        apply_edits
      end

      # Relève les balises de bloc, avec le paragraphe et la ligne de tableau
      # qui les contiennent.
      private def scan_blocks : Nil
        stack = [] of {String, Int32}
        @tokens.each_with_index do |token, index|
          if !token.starts_with?("<")
            block_hits(token, index, stack)
          elsif !markup?(token) && !token.ends_with?("/>")
            name = @flavor.element_name(token)
            if token.starts_with?("</")
              stack.pop?.try { |opened| @closes[opened[1]] = index }
            else
              @parents[index] = stack.last?.try(&.[0]) if @flavor.paragraph?(name)
              stack << {name, index}
            end
          end
        end
      end

      private def block_hits(token : String, index : Int32, stack : Array({String, Int32})) : Nil
        paragraph = stack.reverse.find { |(name, _)| @flavor.paragraph?(name) }.try(&.[1]) || return
        row = stack.reverse.find { |(name, _)| @flavor.row?(name) }.try(&.[1])
        token.scan(BLOCK_RE) do |match|
          name = match[0].lchop("{%").rchop("%}").strip.lchop('-').split.first? || ""
          @hits << Hit.new(index, match.begin, match[0], name, paragraph, row)
        end
      end

      # Blocs ouverts dans une ligne de tableau et fermés dans une autre
      # cellule ou une ligne suivante : balises sorties autour des lignes.
      private def hoist_rows : Nil
        # Blocs ouverts : balise d'ouverture et présence d'un `else`/`elsif`.
        open_blocks = [] of {Hit, Bool}
        @hits.each do |hit|
          case hit.name
          when "for", "if", "unless" then open_blocks << {hit, false}
          when "else", "elsif"
            open_blocks[-1] = {open_blocks[-1][0], true} unless open_blocks.empty?
          when "endfor", "endif", "endunless"
            opening, branched = open_blocks.pop? || next
            hoist_row_block(opening, hit) unless branched && opening.name != "for"
          end
        end
      end

      private def hoist_row_block(opening : Hit, closing : Hit) : Nil
        row = opening.row
        return unless row && opening.paragraph != closing.paragraph
        closing_row = closing.row
        close = closing_row.try { |index| @closes[index]? }
        unless close
          @problems << Fusion::Issue.new("row_block_unclosed", {"tag" => opening.text})
          return
        end
        @before[row] += opening.text
        @after[close] = closing.text + @after[close]
        @removals[opening.token] << opening
        @removals[closing.token] << closing
        @hoisted << opening << closing
      end

      # Paragraphes du corps faits seulement de balises de bloc : remplacés
      # par ces balises.
      private def hoist_paragraphs : Nil
        @hits.reject { |hit| @hoisted.includes?(hit) || hit.row }.group_by(&.paragraph).each do |paragraph, items|
          close = paragraph.try { |index| @closes[index]? }
          next unless paragraph && close && @parents[paragraph]?.try { |parent| @flavor.container?(parent) }
          range = (paragraph..close)
          next if range.any? { |index| @tokens[index].starts_with?("<w:sectPr") }
          next unless paragraph_text(range).matches?(TAGS_ONLY_RE)
          @replaced[paragraph] = items.join(&.text)
          ((paragraph + 1)..close).each { |index| @replaced[index] = "" }
        end
      end

      private def apply_edits : Nil
        @removals.each do |index, items|
          token = @tokens[index]
          items.sort_by(&.offset).reverse_each do |hit|
            token = token[0, hit.offset] + token[(hit.offset + hit.text.size)..]
          end
          @tokens[index] = token
        end
        @replaced.each { |index, text| @tokens[index] = text }
        @before.each { |index, text| @tokens[index] = text + @tokens[index] }
        @after.each { |index, text| @tokens[index] = @tokens[index] + text }
      end

      # Texte d'un paragraphe (fragments de texte seulement).
      private def paragraph_text(range : Range(Int32, Int32)) : String
        stack = [] of String
        String.build do |io|
          range.each do |index|
            token = @tokens[index]
            if token.starts_with?("<")
              next if markup?(token) || token.ends_with?("/>")
              token.starts_with?("</") ? stack.pop? : (stack << @flavor.element_name(token))
            elsif (text_element = @flavor.text_element).nil? || stack.last? == text_element
              io << HTML.unescape(token)
            end
          end
        end
      end
    end
  end
end
