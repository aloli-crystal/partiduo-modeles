# SPDX-License-Identifier: AGPL-3.0-or-later

module Modeles
  # Moteur de fusion (ADR-010 D2) : un seul langage, la syntaxe des
  # gabarits de Marten bridée au contexte de fusion, pour les quatre
  # formats. Point d'entrée du contrôle (`analyze`) et du rendu (`render`).
  module Fusion
    # Contrôle d'un modèle de `format` pour le type de document `kind`
    # (`nil` : sans les mentions obligatoires).
    def self.analyze(format : String, bytes : Bytes, kind : String? = nil) : Report
      if Config.office?(format)
        document = begin
          Office::Document.new(bytes, format)
        rescue error : Office::InvalidPackage
          report = Report.new
          report.error("invalid_package", {"format" => format.upcase, "message" => error.message.to_s})
          return report
        end
        report = Analyzer.analyze(document.source, kind)
        document.problems.each { |issue| report.error(issue.code, issue.params) }
        report
      else
        text = String.new(bytes)
        if !text.valid_encoding? || bytes.includes?(0_u8)
          report = Report.new
          report.error("not_text")
          return report
        end
        Analyzer.analyze(text.lchop('\u{FEFF}'), kind)
      end
    end

    # Rendu d'un modèle avec un document de la Facturation, au format du
    # modèle. `marker` : mention d'un rendu sans valeur (brouillon, aperçu
    # fictif), imprimée en tête du document.
    def self.render(format : String, bytes : Bytes, view : Partiduo::Api::Invoicing::DocumentView,
                    marker : String? = nil) : Bytes
      values = ContextBuilder.new(view, format, marker).build
      if Config.office?(format)
        Office::Document.new(bytes, format).render(values, marker)
      else
        text = String.new(bytes).lchop('\u{FEFF}')
        rendered = Engine.render(text, values, escape: false)
        (marker ? mark_text(format, rendered, Escaper.escape(format, marker)) : rendered).to_slice
      end
    end

    # Mention d'un rendu sans valeur en tête d'un texte : après l'en-tête
    # d'un document AsciiDoc (titre et attributs), en tête d'un Markdown.
    def self.mark_text(format : String, text : String, marker : String) : String
      if format == "asciidoc"
        lines = text.lines(chomp: false)
        header = 0
        if lines.first?.try(&.starts_with?("= "))
          header = 1
          while header < lines.size && !lines[header].strip.empty?
            header += 1
          end
        end
        (lines[0, header] + ["\n*#{marker}*\n\n"] + lines[header..]).join
      else
        "**#{marker}**\n\n#{text}"
      end
    end
  end
end
