# SPDX-License-Identifier: AGPL-3.0-or-later

module Modeles
  module Api
    # Types de document, langues et formats (`Modeles::Config`).
    KINDS   = Config::KINDS
    LOCALES = Config::LOCALES
    FORMATS = Config::FORMATS

    # Extension de fichier d'un format, taille maximale d'un dépôt.
    EXTENSIONS = Config::EXTENSIONS
    MAX_BYTES  = Config::MAX_BYTES

    # Dépôt d'un modèle : nouveau modèle (`template_id` à `nil` ; `name`,
    # `kind`, `locale` exigés) ou nouvelle version d'un modèle existant (le
    # nom, le type et la langue restent ceux du modèle). Le format est
    # déduit de l'extension du fichier (`.adoc`, `.md`, `.odt`, `.docx`) et
    # doit rester celui du modèle.
    record UploadInput,
      filename : String,
      content : Bytes,
      name : String = "",
      kind : String = "",
      locale : String = "",
      template_id : Int64? = nil

    # Remarque d'un contrôle : clé de traduction et paramètres.
    record IssueView, key : String, params : Hash(String, String)

    # Rapport du contrôle au dépôt (ADR-010 D3) : `errors` (le dépôt est
    # refusé), `warnings` (remarques), format reconnu, champs du vocabulaire
    # imprimés par le modèle, et disponibilité du PDF pour ce format.
    record CheckView,
      format : String?,
      errors : Array(IssueView),
      warnings : Array(IssueView),
      fields : Array(String),
      pdf_available : Bool do
      def ok? : Bool
        errors.empty?
      end
    end

    record VersionView,
      id : Int64,
      template_id : Int64,
      number : Int32,
      filename : String,
      byte_size : Int64,
      sha256 : String,
      warnings : Array(IssueView),
      uploaded_by_id : Int64?,
      created_at : Time

    # Modèle : `active_version` est le numéro de la version en service
    # (`nil` : jamais activé), `latest_version` celui de la dernière
    # déposée ; un modèle retiré ne sert plus.
    record TemplateView,
      id : Int64,
      name : String,
      kind : String,
      locale : String,
      format : String,
      active_version : Int32?,
      latest_version : Int32,
      is_default : Bool,
      retired_at : Time?,
      created_at : Time,
      updated_at : Time,
      versions : Array(VersionView) do
      def active? : Bool
        !active_version.nil? && retired_at.nil?
      end

      def retired? : Bool
        !retired_at.nil?
      end

      # Une version plus récente attend son activation.
      def pending_version? : Bool
        active_version.try { |number| number < latest_version } || (active_version.nil? && retired_at.nil?)
      end

      def version(number : Int32) : VersionView?
        versions.find { |version| version.number == number }
      end
    end

    # Critères de la liste des modèles.
    record TemplateQuery,
      kind : String? = nil,
      locale : String? = nil,
      include_retired : Bool = false,
      active_only : Bool = false

    # Rendu conservé (ADR-010 D4) : empreintes du fichier et du PDF, version
    # du modèle ; `pdf_error` : clé de traduction de l'échec de la
    # conversion (vide sinon).
    record RenditionView,
      id : Int64,
      document_id : Int64,
      document_kind : String,
      document_number : String,
      locale : String,
      template_id : Int64,
      template_name : String,
      version_id : Int64,
      version_number : Int32,
      format : String,
      filename : String,
      sha256 : String,
      byte_size : Int64,
      pdf_filename : String?,
      pdf_sha256 : String?,
      pdf_error : String,
      rendered_by_id : Int64?,
      created_at : Time do
      def pdf? : Bool
        !pdf_sha256.nil?
      end
    end

    # Fichier à servir tel quel.
    record FileView, filename : String, content_type : String, content : Bytes

    # Résultat d'un rendu : le fichier au format du modèle, le PDF s'il a
    # été produit, l'échec de la conversion (`pdf_error`, `pdf_detail`) et,
    # pour un document émis, le rendu conservé (`nil` pour un brouillon :
    # aperçu « Brouillon — sans valeur », non conservé).
    record RenderView,
      file : FileView,
      pdf : FileView?,
      pdf_error : String?,
      pdf_detail : String,
      rendition : RenditionView?,
      draft : Bool

    # Convertisseur PDF d'un format (ADR-010 D5) : outil et chemin s'il est
    # déclaré par l'instance.
    # `variable` : variable d'environnement de l'instance qui le déclare.
    record ConverterView, format : String, tool : String, path : String?, timeout_seconds : Int32, variable : String do
      def available? : Bool
        !path.nil?
      end
    end

    # Groupe du vocabulaire de fusion (ADR-010 D2) : objet (`facture`) ou
    # liste (`lignes`, parcourue par `item` dans une boucle), et ses champs.
    record VocabularyGroupView, name : String, list : Bool, item : String?, fields : Array(String)

    # Modèle de départ (ADR-010 D6).
    record StarterView, kind : String, locale : String, format : String, filename : String
  end
end
