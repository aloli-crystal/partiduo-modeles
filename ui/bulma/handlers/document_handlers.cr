# SPDX-License-Identifier: AGPL-3.0-or-later

module Modeles
  module Ui
    # Devis, factures, factures d'acompte et avoirs de la Facturation.
    RENDERABLE = %w[quote invoice deposit_invoice credit_note]

    # Rendus conservés montrés sur la fiche d'un document (les plus récents).
    PANEL_RENDITIONS = 10

    # `/ext/MODELES/documents` : documents à rendre avec un modèle, cherchés
    # par numéro ; les plus récents d'abord.
    class DocumentsHandler < Handler
      def get
        search = query("q")
        documents = Inv.documents(current.actor, Inv::DocumentQuery.new(search: search.presence, limit: 200))
          .select { |document| RENDERABLE.includes?(document.kind) }
          .sort_by! { |document| {document.draft? ? 1 : 0, -(document.issue_date || document.created_at).to_unix, -document.id} }
          .first(50)
        title = I18n.t("modeles_ui.documents.title")
        page("modeles/documents.html", {
          "title"     => title,
          "crumbs"    => crumbs(title),
          "search"    => search,
          "documents" => listed(documents.map { |document| Present.document(document, fmt) }),
        })
      end
    end

    # « Rendre avec un modèle » (ADR-010 D4) pour un document : choix du
    # modèle, PDF si le convertisseur est déclaré, rendus conservés.
    class DocumentHandler < Handler
      def get
        actor = current.actor
        document = Inv.document(actor, id_param)
        templates = Api.templates_for(actor, document.id)
        converters = Api.converters(actor).to_h { |view| {view.format, view} }
        options = templates.map_with_index do |view, index|
          available = converters[view.format]?.try(&.available?) || false
          Ui.row({
            "id"       => view.id.to_s,
            "label"    => "#{view.name} — #{Present.format(view.format)} · #{Present.locale(view.locale)} · v#{view.active_version}",
            "selected" => Ui.flag(index == 0),
            "default"  => Ui.flag(view.is_default),
            "pdf"      => Ui.flag(available),
          })
        end
        title = "#{I18n.t(document.kind_key)} #{document.number || I18n.t("modeles_ui.documents.draft")}"
        renditions = Api.renditions(actor, document.id).map { |view| Present.rendition(view, fmt) }
        page("modeles/document.html", {
          "title"         => title,
          "crumbs"        => crumbs(title, crumb("modeles_ui.documents.title", Ui.url("documents"))),
          "document"      => Present.document(Inv.document(actor, document.id), fmt),
          "draft"         => Ui.flag(document.draft?),
          "renderable"    => Ui.flag(RENDERABLE.includes?(document.kind)),
          "templates"     => listed(options),
          "render_url"    => Ui.url("render", id: document.id),
          "document_url"  => reverse("invoicing:document", id: document.id),
          "renditions"    => listed(renditions),
          "rendered"      => query("rendered").presence,
          "no_pdf_format" => listed(templates.map(&.format).uniq!.reject { |format| converters[format]?.try(&.available?) }
            .map { |format| Present.format(format) }),
          "index_url" => Ui.url("index"),
        })
      end
    end

    # Rendu demandé : un brouillon est rendu en aperçu (fichier servi
    # aussitôt, non conservé) ; un document émis est conservé, puis la page
    # du document le montre dans ses rendus.
    class RenderHandler < Handler
      def get
        go(Ui.url("document", id: id_param))
      end

      def post
        pdf = field("pdf") == "1"
        result = Api.render(current.actor, id_param, field("template_id").to_i64?, pdf: pdf)
        unless rendered = result.value?
          flash["danger"] = messages(result)
          return go(Ui.url("document", id: id_param))
        end
        if rendition = rendered.rendition
          flash["success"] = I18n.t("modeles_ui.flash.rendered", filename: rendition.filename)
          if error = rendered.pdf_error
            flash["warning"] = I18n.t(error, detail: rendered.pdf_detail)
          end
          return go("#{Ui.url("document", id: id_param)}?rendered=#{rendition.id}")
        end
        if pdf && (file = rendered.pdf)
          return Present.file(file)
        end
        Present.file(rendered.file)
      end
    end

    # `/ext/MODELES/renditions` : historique des rendus conservés.
    class RenditionsHandler < Handler
      def get
        title = I18n.t("modeles_ui.renditions.title")
        renditions = Api.renditions(current.actor, limit: 200).map { |view| Present.rendition(view, fmt) }
        page("modeles/renditions.html", {
          "title"      => title,
          "crumbs"     => crumbs(title),
          "renditions" => listed(renditions),
        })
      end
    end

    # Fichier d'un rendu conservé : `file` (format du modèle) ou `pdf`.
    class RenditionFileHandler < Handler
      def get
        variant = params["variant"].to_s
        raise Partiduo::Api::NotFound.new("modeles_rendition_file", id_param) unless variant.in?("file", "pdf")
        Present.file(Api.rendition_file(current.actor, id_param, variant), inline: variant == "pdf")
      end
    end
  end
end
