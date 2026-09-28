# SPDX-License-Identifier: AGPL-3.0-or-later

module Modeles
  module Fusion
    # Échappement des valeurs du contexte de fusion selon le format
    # (ADR-010 D2) : une valeur de la facture (nom d'un client, désignation)
    # ne doit jamais être lue comme de la mise en forme.
    #
    # * ODT, DOCX : les caractères spéciaux du XML sont échappés par le
    #   moteur de gabarits de Marten à l'impression (`&`, `<`, `>`, `"`,
    #   `'`) ; les retours à la ligne et tabulations deviennent des marques,
    #   remplacées après la fusion par l'élément du format (`<w:br/>`,
    #   `<text:line-break/>`…) ; les caractères interdits en XML sont
    #   retirés.
    # * AsciiDoc : les caractères actifs deviennent des références numériques
    #   (`&#42;` pour `*`), que les convertisseurs d'AsciiDoc rendent tels
    #   quels ; retour à la ligne : saut de ligne forcé (` +`).
    # * Markdown : les caractères actifs sont précédés d'une barre oblique
    #   inverse (CommonMark) ; retour à la ligne : saut forcé (`\`), ou
    #   espace dans une cellule de tableau (`inline`).
    module Escaper
      # Marques d'un retour à la ligne et d'une tabulation dans une valeur
      # (zone d'usage privé d'Unicode, jamais produite par un traitement de
      # texte), remplacées après la fusion d'un ODT ou d'un DOCX.
      NEWLINE = '\u{E000}'
      TAB     = '\u{E001}'

      ASCIIDOC_ACTIVE = {'*', '_', '`', '#', '+', '^', '~', '{', '}', '[', ']', '<', '>', '|', '\\', '&'}
      # Début de ligne actif en AsciiDoc : titre de bloc, section, liste,
      # délimiteur, commentaire, attribut.
      ASCIIDOC_LINE_START = {'.', '=', '-', '\'', '/', ':'}
      MARKDOWN_ACTIVE     = {'\\', '`', '*', '_', '{', '}', '[', ']', '<', '>', '#', '|', '~', '&', '!'}

      # Valeur prête à être insérée dans un modèle au format `format` ;
      # `inline` : valeur d'une ligne de tableau (sans retour à la ligne en
      # Markdown).
      def self.escape(format : String, value : String, inline : Bool = false) : String
        text = value.gsub("\r\n", "\n").tr("\r", "\n")
        case format
        when "odt", "docx" then xml(text)
        when "asciidoc"    then asciidoc(text)
        when "markdown"    then markdown(text, inline)
        else                    text
        end
      end

      def self.xml(text : String) : String
        String.build do |io|
          text.each_char do |char|
            case char
            when '\n' then io << NEWLINE
            when '\t' then io << TAB
            else
              io << char unless xml_forbidden?(char)
            end
          end
        end
      end

      # Caractère interdit dans un document XML 1.0 (contrôles, hors
      # tabulation et retours à la ligne ; marques d'usage privé réservées).
      def self.xml_forbidden?(char : Char) : Bool
        code = char.ord
        (code < 0x20 && !char.in?('\t', '\n', '\r')) || char == NEWLINE || char == TAB || (0xFFFE..0xFFFF).includes?(code)
      end

      def self.asciidoc(text : String) : String
        text.split('\n').map do |line|
          line = line.lstrip
          String.build do |io|
            line.each_char_with_index do |char, position|
              if ASCIIDOC_ACTIVE.includes?(char) ||
                 (position == 0 && ASCIIDOC_LINE_START.includes?(char)) ||
                 (char == '-' && line[position + 1]? == '-')
                io << "&#" << char.ord << ';'
              else
                io << char
              end
            end
          end
        end.reject(&.empty?).join(" +\n")
      end

      def self.markdown(text : String, inline : Bool) : String
        lines = text.split('\n').map(&.strip).reject(&.empty?).map do |line|
          escaped = String.build do |io|
            line.each_char { |char| io << '\\' if MARKDOWN_ACTIVE.includes?(char); io << char }
          end
          # Début de ligne lu comme une liste, un titre souligné ou une liste
          # numérotée (`1.`, `1)`).
          escaped = "\\#{escaped}" if escaped.starts_with?('-') || escaped.starts_with?('+') || escaped.starts_with?('=')
          escaped.sub(/\A(\d+)([.)])(?=\s|\z)/) { "#{$1}\\#{$2}" }
        end
        lines.join(inline ? " " : "\\\n")
      end
    end
  end
end
