# SPDX-License-Identifier: AGPL-3.0-or-later

module Modeles
  module Ui
    # Ligne présentée à un gabarit : textes déjà mis en forme, par nom, et
    # listes de lignes (`children`). Objet plutôt que grand `Hash` : Marten
    # ne retrouve pas les clés d'un grand `Hash` (BLOCAGES B-EINV-001 du
    # cœur).
    class Row
      include Marten::Template::Object

      getter values : Hash(String, String?)
      getter children : Hash(String, Array(Row))

      def initialize(@values : Hash(String, String?), @children = {} of String => Array(Row))
      end

      def resolve_template_attribute(key : String)
        return @children[key] if @children.has_key?(key)
        @values[key]?
      end
    end

    def self.row(values : Hash(String, String?), children = {} of String => Array(Row)) : Row
      Row.new(values, children)
    end

    def self.row(values : Hash(String, String), children = {} of String => Array(Row)) : Row
      Row.new(values.transform_values(&.as(String?)), children)
    end

    def self.url(name : String, **params) : String
      Marten.routes.reverse("modeles:#{name}", **params)
    end

    def self.flag(value : Bool) : String?
      value ? "1" : nil
    end

    # Présentations communes aux écrans de l'extension.
    module Present
      alias Api = Modeles::Api

      def self.kind(kind : String) : String
        I18n.t("modeles.kinds.#{kind}")
      end

      def self.locale(locale : String) : String
        I18n.t("modeles.locales.#{locale}")
      end

      def self.format(format : String) : String
        I18n.t("modeles.formats.#{format}")
      end

      # Statut d'un modèle : `active`, `pending` (déposé, jamais activé),
      # `retired`.
      def self.status(view : Api::TemplateView) : String
        if view.retired?
          "retired"
        elsif view.active?
          "active"
        else
          "pending"
        end
      end

      def self.status_class(status : String) : String
        case status
        when "active"  then "is-success"
        when "pending" then "is-warning"
        else                "is-light"
        end
      end

      def self.template(view : Api::TemplateView, fmt : PartiduoUi::Format) : Row
        status = status(view)
        Ui.row({
          "id"           => view.id.to_s,
          "url"          => Ui.url("template", id: view.id),
          "name"         => view.name,
          "kind"         => kind(view.kind),
          "locale"       => locale(view.locale),
          "format"       => format(view.format),
          "format_code"  => view.format,
          "status"       => status,
          "status_label" => I18n.t("modeles_ui.statuses.#{status}"),
          "status_class" => status_class(status),
          "active"       => view.active_version.try { |number| "v#{number}" },
          "latest"       => "v#{view.latest_version}",
          "pending"      => Ui.flag(view.pending_version?),
          "default"      => Ui.flag(view.is_default),
          "updated"      => fmt.datetime(view.updated_at),
        })
      end

      def self.issue(issue : Api::IssueView) : String
        Api.message(issue)
      end

      def self.rendition(view : Api::RenditionView, fmt : PartiduoUi::Format) : Row
        Ui.row({
          "id"           => view.id.to_s,
          "document"     => view.document_number,
          "document_url" => Ui.url("document", id: view.document_id),
          "kind"         => I18n.t("invoicing.kinds.#{view.document_kind}"),
          "template"     => view.template_name,
          "template_url" => Ui.url("template", id: view.template_id),
          "version"      => "v#{view.version_number}",
          "format"       => format(view.format),
          "filename"     => view.filename,
          "file_url"     => Ui.url("rendition_file", id: view.id, variant: "file"),
          "sha256"       => view.sha256,
          "sha_short"    => view.sha256[0, 12],
          "pdf_url"      => view.pdf? ? Ui.url("rendition_file", id: view.id, variant: "pdf") : nil,
          "pdf_sha256"   => view.pdf_sha256,
          "pdf_error"    => view.pdf_error.presence.try { |key| I18n.t(key, detail: "") },
          "rendered_at"  => fmt.datetime(view.created_at),
        })
      end

      def self.document(document : Partiduo::Api::Invoicing::DocumentView, fmt : PartiduoUi::Format) : Row
        Ui.row({
          "id"       => document.id.to_s,
          "url"      => Ui.url("document", id: document.id),
          "number"   => document.number || I18n.t("modeles_ui.documents.draft"),
          "draft"    => Ui.flag(document.draft?),
          "kind"     => I18n.t(document.kind_key),
          "status"   => I18n.t(document.status_key),
          "customer" => document.customer.name,
          "date"     => (document.issue_date || document.created_at).try { |date| fmt.date(date) },
          "total"    => fmt.amount(document.totals.total_gross),
          "currency" => document.currency_code,
          "locale"   => locale(document.locale),
        })
      end

      # Réponse d'un fichier : `inline` (PDF affiché) ou téléchargement.
      def self.file(file : Api::FileView, inline : Bool = false) : Marten::HTTP::Response
        response = Marten::HTTP::Response.new(content: String.new(file.content), content_type: file.content_type)
        disposition = inline ? "inline" : "attachment"
        response["Content-Disposition"] = %(#{disposition}; filename="#{file.filename.gsub(/["\\\r\n]/, "_")}")
        response["X-Content-Type-Options"] = "nosniff"
        response["Cache-Control"] = "private, no-store"
        response
      end
    end
  end
end
