# SPDX-License-Identifier: AGPL-3.0-or-later

module Modeles
  module Fusion
    # Le gabarit ne passe pas le contrôle : il n'est jamais rendu.
    class TemplateRejected < Exception
      getter report : Report

      def initialize(@report : Report)
        super("modèle refusé : #{@report.errors.map(&.code).join(", ")}")
      end
    end

    # Échec du rendu d'un gabarit contrôlé (valeur inattendue, document
    # produit illisible).
    class RenderError < Exception
    end

    # Fusion d'un gabarit avec un contexte (ADR-010 D2) : le moteur de
    # gabarits de Marten, sans producteur de contexte (ni requête, ni
    # utilisateur, ni réglages), avec les seules valeurs du contexte de
    # fusion. Le gabarit est contrôlé avant chaque rendu (`Analyzer`) : une
    # balise ou un filtre hors de la liste admise ne s'exécute jamais.
    module Engine
      # Rend `source` ; `escape` : échappement XML par Marten à l'impression
      # (ODT, DOCX) ; sinon les valeurs sont déjà échappées pour AsciiDoc ou
      # Markdown.
      def self.render(source : String, values : Hash(String, Marten::Template::Value), escape : Bool) : String
        report = Analyzer.analyze(source)
        raise TemplateRejected.new(report) unless report.ok?
        template = Marten::Template::Template.new(source)
        context = Marten::Template::Context.new(values)
        context.with_escape(escape) { |scoped| template.render(scoped) }
      rescue error : Marten::Template::Errors::UnknownVariable
        raise RenderError.new(error.message)
      rescue error : Marten::Template::Errors::UnsupportedType
        raise RenderError.new(error.message)
      rescue error : Marten::Template::Errors::UnsupportedValue
        raise RenderError.new(error.message)
      rescue error : Marten::Template::Errors::InvalidSyntax
        raise RenderError.new(error.message)
      end
    end
  end
end
