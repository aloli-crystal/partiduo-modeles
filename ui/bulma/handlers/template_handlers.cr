# SPDX-License-Identifier: AGPL-3.0-or-later

module Modeles
  module Ui
    # `/ext/MODELES/` : modèles déposés, dépôt d'un modèle (administrateur),
    # modèles de départ, convertisseurs PDF, vocabulaire de fusion.
    class IndexHandler < Handler
      def get
        show({"name" => "", "kind" => "invoice", "locale" => I18n.locale.to_s}, {} of String => Array(String), [] of String)
      end

      def show(values : Hash(String, String), errors : Hash(String, Array(String)), report : Array(String),
               status : Int32 = 200) : Marten::HTTP::Response
        actor = current.actor
        templates = Api.templates(actor, Api::TemplateQuery.new(include_retired: query("retired") == "1"))
        page("modeles/index.html", {
          "title"         => I18n.t("modeles_ui.index.title"),
          "crumbs"        => crumbs,
          "templates"     => listed(templates.map { |view| Present.template(view, fmt) }),
          "show_retired"  => Ui.flag(query("retired") == "1"),
          "can_admin"     => Ui.flag(can_admin?),
          "values"        => Ui.row(values),
          "errors"        => errors,
          "report"        => listed(report),
          "kinds"         => choices(Api::KINDS, values["kind"], "modeles.kinds"),
          "locales"       => choices(Api::LOCALES, values["locale"], "modeles.locales"),
          "starters"      => starters,
          "locale_labels" => Api::LOCALES.map { |locale| Present.locale(locale) },
          "converters"    => Api.converters(actor).map { |view| converter(view) },
          "vocabulary"    => vocabulary,
          "history_url"   => Ui.url("renditions"),
          "max_mb"        => (Api::MAX_BYTES // (1024 * 1024)).to_s,
        }, status: status)
      end

      private def starters : Array(Row)
        Api::KINDS.map do |kind|
          locales = Api::LOCALES.map do |locale|
            links = Api::FORMATS.map do |format|
              Ui.row({"label" => I18n.t("modeles_ui.formats_short.#{format}"), "title" => Present.format(format),
                      "url" => Ui.url("starter", kind: kind, locale: locale, format: format)})
            end
            Ui.row({"label" => Present.locale(locale), "code" => locale}, {"links" => links})
          end
          Ui.row({"label" => Present.kind(kind)}, {"locales" => locales})
        end
      end

      private def converter(view : Api::ConverterView) : Row
        Ui.row({
          "format"    => Present.format(view.format),
          "tool"      => view.tool,
          "path"      => view.path,
          "timeout"   => view.timeout_seconds.to_s,
          "variable"  => view.variable,
          "available" => Ui.flag(view.available?),
        })
      end

      private def vocabulary : Array(Row)
        Api.vocabulary(current.actor).map do |group|
          prefix = group.item || group.name
          rows = group.fields.map do |field|
            Ui.row({"field" => "#{prefix}.#{field}", "description" => I18n.t("modeles.vocabulary.#{group.name}.#{field}")})
          end
          Ui.row({"group" => group.name, "label" => I18n.t("modeles.vocabulary.groups.#{group.name}"),
                  "loop" => group.item.try { |item| "{% for #{item} in #{group.name} %}…{% endfor %}" }}, {"fields" => rows})
        end
      end
    end

    # Dépôt d'un modèle (nouveau modèle, ou nouvelle version avec
    # `template_id`) : contrôlé, refusé avec le rapport, ou enregistré.
    class UploadHandler < IndexHandler
      def get
        go(Ui.url("index"))
      end

      def post
        values = {"name" => field("name"), "kind" => field("kind"), "locale" => field("locale")}
        template_id = field("template_id").to_i64?
        uploaded = upload
        if uploaded.nil? || uploaded[1].empty?
          errors = {"file" => [I18n.t("modeles_ui.errors.file_missing")]}
          return template_id ? refused(template_id, errors, [] of String) : show(values, errors, [] of String, 422)
        end
        filename, content = uploaded
        result = Api.upload(current.actor, Api::UploadInput.new(filename: filename, content: content, name: values["name"],
          kind: values["kind"], locale: values["locale"], template_id: template_id))
        if view = result.value?
          flash["success"] = I18n.t("modeles_ui.flash.uploaded", version: view.latest_version)
          return go(Ui.url("template", id: view.id))
        end
        errors, report = upload_errors(result.errors)
        template_id ? refused(template_id, errors, report) : show(values, errors, report, 422)
      end

      private def refused(id : Int64, errors : Hash(String, Array(String)), report : Array(String)) : Marten::HTTP::Response
        TemplatePage.new(self).render(id, errors, report, 422)
      end
    end

    # Fiche d'un modèle : versions, aperçu, activation, défaut, retrait,
    # dépôt d'une nouvelle version.
    class TemplateHandler < Handler
      def get
        TemplatePage.new(self).render(id_param, {} of String => Array(String), [] of String)
      end
    end

    # Page d'un modèle, partagée par la fiche et le dépôt refusé d'une
    # nouvelle version.
    struct TemplatePage
      def initialize(@handler : Handler)
      end

      def render(id : Int64, errors : Hash(String, Array(String)), report : Array(String),
                 status : Int32 = 200) : Marten::HTTP::Response
        handler = @handler
        actor = handler.current.actor
        view = Api.template(actor, id)
        fmt = handler.fmt
        admin = handler.can_admin?
        pdf = Api.pdf_available?(actor, view.format)
        versions = view.versions.map do |version|
          Ui.row({
            "number"      => version.number.to_s,
            "label"       => "v#{version.number}",
            "filename"    => version.filename,
            "size"        => I18n.t("modeles_ui.template.size", size: fmt.number(BigDecimal.new(version.byte_size) / 1024, 0)),
            "uploaded"    => fmt.datetime(version.created_at),
            "sha_short"   => version.sha256[0, 12],
            "sha256"      => version.sha256,
            "active"      => Ui.flag(version.number == view.active_version),
            "file_url"    => Ui.url("version_file", id: view.id, number: version.number),
            "preview_url" => Ui.url("preview", id: view.id, number: version.number),
            "pdf_url"     => pdf ? "#{Ui.url("preview", id: view.id, number: version.number)}?pdf=1" : nil,
            "activate"    => Ui.flag(admin && version.number != view.active_version),
          }, {"warnings" => version.warnings.map { |warning| Ui.row({"text" => Present.issue(warning)}) }})
        end
        title = view.name
        handler.page("modeles/template.html", {
          "title"        => title,
          "crumbs"       => handler.crumbs(title),
          "template"     => Present.template(view, fmt),
          "versions"     => versions,
          "can_admin"    => Ui.flag(admin),
          "pdf"          => Ui.flag(pdf),
          "variable"     => Api.converters(actor).find { |item| item.format == view.format }.try(&.variable),
          "activate_url" => admin ? Ui.url("activate", id: view.id) : nil,
          "default_url"  => admin && view.active? ? Ui.url("default", id: view.id) : nil,
          "retire_url"   => admin && !view.retired? ? Ui.url("retire", id: view.id) : nil,
          "upload_url"   => admin && !view.retired? ? Ui.url("upload") : nil,
          "is_default"   => Ui.flag(view.is_default),
          "errors"       => errors,
          "report"       => report.empty? ? nil : report,
          "accept"       => ".#{Api::EXTENSIONS[view.format]}",
          "max_mb"       => (Api::MAX_BYTES // (1024 * 1024)).to_s,
        }, status: status)
      end
    end

    # Fichier d'une version, tel que déposé.
    class VersionFileHandler < Handler
      def get
        Present.file(Api.version_file(current.actor, id_param, params["number"].to_s.to_i))
      end
    end

    # Aperçu d'une version avec un document fictif (ADR-010 D3) : fichier au
    # format du modèle, ou PDF (`pdf=1`) si le convertisseur est déclaré.
    class PreviewHandler < Handler
      def get
        pdf = query("pdf") == "1"
        result = Api.preview(current.actor, id_param, params["number"].to_s.to_i, pdf: pdf)
        unless rendered = result.value?
          flash["danger"] = messages(result)
          return go(Ui.url("template", id: id_param))
        end
        if pdf
          if file = rendered.pdf
            return Present.file(file, inline: true)
          end
          flash["danger"] = I18n.t(rendered.pdf_error || "modeles.errors.pdf.unavailable", detail: rendered.pdf_detail)
          return go(Ui.url("template", id: id_param))
        end
        Present.file(rendered.file)
      end
    end

    # Commandes d'administration d'un modèle.
    abstract class CommandHandler < Handler
      abstract def run(id : Int64) : Partiduo::Api::Result(Api::TemplateView)
      abstract def done_key : String

      def get
        go(Ui.url("template", id: id_param))
      end

      def post
        result = run(id_param)
        if result.success?
          flash["success"] = I18n.t(done_key)
        else
          flash["danger"] = messages(result)
        end
        go(Ui.url("template", id: id_param))
      end
    end

    class ActivateHandler < CommandHandler
      def run(id : Int64) : Partiduo::Api::Result(Api::TemplateView)
        Api.activate(current.actor, id, field("version").to_i?)
      end

      def done_key : String
        "modeles_ui.flash.activated"
      end
    end

    class DefaultHandler < CommandHandler
      def run(id : Int64) : Partiduo::Api::Result(Api::TemplateView)
        field("unset") == "1" ? Api.unset_default(current.actor, id) : Api.set_default(current.actor, id)
      end

      def done_key : String
        field("unset") == "1" ? "modeles_ui.flash.default_unset" : "modeles_ui.flash.default_set"
      end
    end

    class RetireHandler < CommandHandler
      def run(id : Int64) : Partiduo::Api::Result(Api::TemplateView)
        Api.retire(current.actor, id)
      end

      def done_key : String
        "modeles_ui.flash.retired"
      end
    end

    # Modèle de départ à télécharger (ADR-010 D6).
    class StarterHandler < Handler
      def get
        Present.file(Api.starter_file(current.actor, params["kind"].to_s, params["locale"].to_s, params["format"].to_s))
      end
    end
  end
end
