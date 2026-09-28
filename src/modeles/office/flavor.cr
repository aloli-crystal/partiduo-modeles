# SPDX-License-Identifier: AGPL-3.0-or-later

module Modeles
  module Office
    # Particularités d'un format de traitement de texte : parties XML qui
    # portent du texte, éléments de paragraphe, de ligne de tableau, de
    # texte, et remplacement des marques de retour à la ligne.
    abstract class Flavor
      def self.for(format : String) : Flavor
        case format
        when "odt"  then Odt.new
        when "docx" then Docx.new
        else             raise ArgumentError.new("format sans archive : #{format}")
        end
      end

      abstract def format : String

      # Parties XML fusionnées, dans l'ordre de l'archive.
      abstract def parts(package : Package) : Array(String)

      # Contrôle que l'archive est bien un document de ce format.
      abstract def check(package : Package) : Nil

      abstract def paragraph?(name : String) : Bool
      abstract def row?(name : String) : Bool
      abstract def table?(name : String) : Bool

      # Élément qui porte le texte du paragraphe (`w:t`) ; `nil` : tout
      # texte du paragraphe compte (ODT).
      abstract def text_element : String?

      # Parents d'un paragraphe qui peut être remplacé par les seules balises
      # de bloc qu'il contient (corps, section, en-tête, pied de page).
      abstract def container?(name : String) : Bool

      # Élément vide qui vaut un ou plusieurs espaces (`text:s` en ODT).
      def spaces(tag : String) : Int32?
        nil
      end

      # Après la fusion : marques de retour à la ligne et de tabulation
      # remplacées par les éléments du format.
      abstract def finish(xml : String) : String

      # Paragraphe « Brouillon — sans valeur » ajouté en tête du corps.
      abstract def mark(xml : String, marker : String) : String

      def element_name(tag : String) : String
        tag.lchop('<').lchop('/').split(/[\s\/>]/, 2).first
      end
    end

    # OpenDocument texte (ODT) : `content.xml` (corps) et `styles.xml`
    # (en-têtes et pieds de page des pages maîtresses).
    class Odt < Flavor
      MIMETYPE = "application/vnd.oasis.opendocument.text"

      def format : String
        "odt"
      end

      def parts(package : Package) : Array(String)
        %w[content.xml styles.xml].select { |name| package[name]? }
      end

      def check(package : Package) : Nil
        mimetype = package.text(Package::MIMETYPE).try(&.strip)
        raise InvalidPackage.new("mimetype #{mimetype.inspect}") unless mimetype == MIMETYPE
        raise InvalidPackage.new("content.xml absent") unless package["content.xml"]?
      end

      def paragraph?(name : String) : Bool
        name.in?("text:p", "text:h")
      end

      def row?(name : String) : Bool
        name == "table:table-row"
      end

      def table?(name : String) : Bool
        name == "table:table"
      end

      def text_element : String?
        nil
      end

      def container?(name : String) : Bool
        name.in?("office:text", "text:section", "style:header", "style:footer", "style:header-left",
          "style:footer-left", "style:header-first", "style:footer-first")
      end

      def spaces(tag : String) : Int32?
        return unless element_name(tag) == "text:s"
        tag.match(/text:c="(\d+)"/).try(&.[1].to_i) || 1
      end

      def finish(xml : String) : String
        xml.gsub(Fusion::Escaper::NEWLINE, "<text:line-break/>").gsub(Fusion::Escaper::TAB, "<text:tab/>")
      end

      def mark(xml : String, marker : String) : String
        body = xml.index(/<office:text[\s>]/) || return xml
        first = xml.index(/<(?:text:p|text:h|table:table|text:section|text:list)[\s>\/]/, body) || return xml
        paragraph = %(<text:p><text:span>#{HTML.escape(marker)}</text:span></text:p>)
        xml.insert(first, paragraph)
      end
    end

    # Office Open XML (DOCX) : `word/document.xml`, en-têtes et pieds de page.
    class Docx < Flavor
      def format : String
        "docx"
      end

      def parts(package : Package) : Array(String)
        package.names.select { |name| name == "word/document.xml" || name.matches?(/\Aword\/(header|footer)\d*\.xml\z/) }
      end

      def check(package : Package) : Nil
        raise InvalidPackage.new("[Content_Types].xml absent") unless package["[Content_Types].xml"]?
        raise InvalidPackage.new("word/document.xml absent") unless package["word/document.xml"]?
      end

      def paragraph?(name : String) : Bool
        name == "w:p"
      end

      def row?(name : String) : Bool
        name == "w:tr"
      end

      def table?(name : String) : Bool
        name == "w:tbl"
      end

      def text_element : String?
        "w:t"
      end

      def container?(name : String) : Bool
        name.in?("w:body", "w:hdr", "w:ftr")
      end

      def finish(xml : String) : String
        xml.gsub(Fusion::Escaper::NEWLINE, %(</w:t><w:br/><w:t xml:space="preserve">))
          .gsub(Fusion::Escaper::TAB, %(</w:t><w:tab/><w:t xml:space="preserve">))
      end

      def mark(xml : String, marker : String) : String
        body = xml.match(/<w:body>/) || return xml
        paragraph = %(<w:p><w:r><w:rPr><w:b/><w:color w:val="C00000"/></w:rPr><w:t xml:space="preserve">) +
                    HTML.escape(marker) + %(</w:t></w:r></w:p>)
        xml.insert(body.end, paragraph)
      end
    end
  end
end
