# SPDX-License-Identifier: AGPL-3.0-or-later

module Modeles
  # Valeurs fermées de l'extension (vérifiées aussi en base par la
  # migration 0001) et configuration de l'instance.
  module Config
    # Types de document d'un modèle (ADR-010 D4) : la facture d'acompte se
    # rend avec les modèles de facture.
    KINDS = %w[invoice quote credit_note]

    # Langues d'un document de la Facturation.
    LOCALES = %w[fr en nl]

    # Formats d'un modèle (ADR-010 D2), dans l'ordre de l'écran.
    FORMATS = %w[asciidoc markdown odt docx]

    EXTENSIONS = {
      "asciidoc" => "adoc",
      "markdown" => "md",
      "odt"      => "odt",
      "docx"     => "docx",
    }

    CONTENT_TYPES = {
      "asciidoc" => "text/asciidoc",
      "markdown" => "text/markdown",
      "odt"      => "application/vnd.oasis.opendocument.text",
      "docx"     => "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
      "pdf"      => "application/pdf",
    }

    # Taille maximale d'un modèle déposé (celle des pièces jointes du socle).
    MAX_BYTES = Partiduo::Core::Attachments::MAX_BYTES

    # Type de document d'un modèle pour une nature de la Facturation ; `nil`
    # si la nature ne se rend pas avec un modèle (commande, bon de livraison).
    def self.kind_of(document_kind : String) : String?
      case document_kind
      when "invoice", "deposit_invoice" then "invoice"
      when "quote"                      then "quote"
      when "credit_note"                then "credit_note"
      end
    end

    # Format déduit de l'extension du fichier déposé.
    def self.format_of(filename : String) : String?
      case File.extname(filename).downcase
      when ".adoc", ".asciidoc", ".asc" then "asciidoc"
      when ".md", ".markdown"           then "markdown"
      when ".odt"                       then "odt"
      when ".docx"                      then "docx"
      end
    end

    def self.office?(format : String) : Bool
      format.in?("odt", "docx")
    end
  end
end
