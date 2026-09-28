# SPDX-License-Identifier: AGPL-3.0-or-later

require "xml"

module Modeles
  module Office
    # Modèle ODT ou DOCX : archive lue, parties XML normalisées (`Normalizer`),
    # prêtes pour le contrôle et la fusion.
    class Document
      getter flavor : Flavor
      getter package : Package
      # Partie → XML normalisé.
      getter parts : Hash(String, String)
      getter problems : Array(Fusion::Issue)

      def initialize(bytes : Bytes, format : String)
        @flavor = Flavor.for(format)
        @package = Package.read(bytes)
        @flavor.check(@package)
        @parts = {} of String => String
        @problems = [] of Fusion::Issue
        @flavor.parts(@package).each do |name|
          xml = @package.text(name) || next
          raise InvalidPackage.new("#{name} n'est pas en UTF-8") unless xml.valid_encoding?
          normalized, problems = Normalizer.normalize(xml, @flavor)
          @parts[name] = normalized
          @problems.concat(problems)
        end
      end

      # Texte soumis au contrôle : toutes les parties, dans l'ordre.
      def source : String
        @parts.values.join('\n')
      end

      # Document fusionné ; `marker` : paragraphe « Brouillon — sans valeur »
      # en tête du corps. Lève `Fusion::RenderError` si une partie produite
      # n'est plus un XML bien formé.
      def render(values : Hash(String, Marten::Template::Value), marker : String? = nil) : Bytes
        package = Package.new(@package.entries.dup)
        body = @flavor.parts(@package).first?
        @parts.each do |name, xml|
          rendered = @flavor.finish(Fusion::Engine.render(xml, values, escape: true))
          rendered = @flavor.mark(rendered, marker) if marker && name == body
          Document.well_formed!(rendered, name)
          package[name] = rendered
        end
        package.to_bytes
      end

      def self.well_formed!(xml : String, name : String) : Nil
        XML.parse(xml, XML::ParserOptions::NONET)
      rescue error : XML::Error
        raise Fusion::RenderError.new("#{name} : #{error.message}")
      end
    end
  end
end
