# SPDX-License-Identifier: AGPL-3.0-or-later

module Modeles
  # Contrat public de l'extension MODELES (ADR-010), sur le modèle de
  # `Partiduo::Api` : acteur en premier argument, contrôle d'accès en
  # première ligne, objets de vue immuables, erreurs par champ. L'interface
  # de l'extension (`ui/bulma/`) ne voit que ce module.
  #
  # Permissions (ADR-010 D7) : `modeles.read` (rendre, télécharger),
  # `modeles.admin` (déposer, activer, désigner par défaut, retirer). Les
  # documents sont lus par `Partiduo::Api::Invoicing` avec l'acteur : il
  # faut aussi `invoicing.invoice.read` pour rendre un document.
  #
  # Le rendu ne modifie jamais la facture (ni numéro, ni montants, ni
  # empreinte) : l'extension ne fait que la lire.
  module Api
    alias Actor = Partiduo::Api::Actor
    alias Guard = Partiduo::Api::Guard
    alias Result = Partiduo::Api::Result
    alias FieldError = Partiduo::Api::FieldError
    alias Transaction = Partiduo::Api::Transaction
    alias Inv = Partiduo::Api::Invoicing

    MODULE_CODE = Modeles::CODE
    READ        = "modeles.read"
    ADMIN       = "modeles.admin"

    # Nombre maximal de rendus rendus par `renditions`.
    MAX_LIMIT = 500

    # --- Modèles -----------------------------------------------------------------

    def self.templates(actor : Actor, query : TemplateQuery = TemplateQuery.new) : Array(TemplateView)
      authorize!(actor, READ)
      rows = Template.all
      query.kind.try { |kind| rows = rows.filter(kind: kind) }
      query.locale.try { |locale| rows = rows.filter(locale: locale) }
      rows = rows.filter(retired_at__isnull: true) unless query.include_retired
      rows = rows.filter(active_version__isnull: false, retired_at__isnull: true) if query.active_only
      rows.order(:kind, :locale, :name, :id).to_a.map { |row| Templates.view(row) }
    end

    def self.template(actor : Actor, id : Int64) : TemplateView
      authorize!(actor, READ)
      Templates.view(Templates.find!(id))
    end

    # Modèle par défaut d'un type de document et d'une langue, s'il y en a un.
    def self.default_template(actor : Actor, kind : String, locale : String) : TemplateView?
      authorize!(actor, READ)
      Template.filter(kind: kind, locale: locale, is_default: true).first.try { |row| Templates.view(row) }
    end

    # Contrôle d'un modèle sans rien enregistrer (rapport de dépôt, D3) ;
    # `template_id` : nouvelle version d'un modèle existant (son type et son
    # format s'imposent).
    def self.check(actor : Actor, input : UploadInput) : CheckView
      authorize!(actor, ADMIN)
      if id = input.template_id
        template = Templates.find!(id)
        Templates.check(input.filename, input.content, template.kind, template.format)
      else
        Templates.check(input.filename, input.content, input.kind)
      end
    end

    # Dépôt d'un modèle (ADR-010 D3) : contrôlé, puis enregistré comme
    # nouveau modèle (version 1) ou nouvelle version d'un modèle existant.
    # Un modèle incomplet est refusé avec la liste de ce qui manque
    # (erreurs sous `content`). La version déposée n'est pas en service tant
    # qu'elle n'est pas activée (`activate`), après son aperçu.
    def self.upload(actor : Actor, input : UploadInput) : Result(TemplateView)
      authorize!(actor, ADMIN)
      existing = input.template_id.try { |id| Templates.find!(id) }
      errors = existing ? [] of FieldError : Templates.field_errors(input)
      if existing && existing.retired_at
        errors << FieldError.base("modeles.errors.template.retired")
      end
      kind = existing.try(&.kind) || input.kind
      report = Templates.check(input.filename, input.content, Config::KINDS.includes?(kind) ? kind : nil, existing.try(&.format))
      report.errors.each { |issue| errors << FieldError.new("content", issue.key, issue.params) }
      format = report.format
      return Result(TemplateView).failure(errors) unless errors.empty? && format

      Transaction.run do
        template = if existing
                     Templates.lock!(existing.id!.to_i64)
                   else
                     Template.create!(name: input.name.strip, kind: input.kind, locale: input.locale, format: format,
                       is_default: false, created_by_id: actor.user_id)
                   end
        template_id = template.id!.to_i64
        number = Templates.latest_number(template_id) + 1
        filename = Files.clean(input.filename).presence || "modele.#{Config::EXTENSIONS[format]}"
        file = begin
          Files.store(filename, Config::CONTENT_TYPES[format], input.content)
        rescue error : StorageRefused
          # Refus du socle (signature d'une archive ODT ou DOCX, taille) :
          # erreurs sous `content`, le modèle éventuellement créé est annulé.
          next Result(TemplateView).failure(error.errors.map { |item| FieldError.new("content", item.key, item.params) })
        end
        TemplateVersion.create!(template_id: template_id, number: number, file_id: file.id, filename: filename,
          byte_size: input.content.size.to_i64, sha256: file.sha256!, warnings: Templates.warnings_json(report.warnings),
          uploaded_by_id: actor.user_id)
        template.save!
        Result(TemplateView).success(Templates.view(template))
      end
    end

    # Met en service une version (la dernière par défaut) ; un modèle retiré
    # redevient actif.
    def self.activate(actor : Actor, id : Int64, version : Int32? = nil) : Result(TemplateView)
      authorize!(actor, ADMIN)
      Transaction.run do
        template = Templates.lock!(id)
        number = version || Templates.latest_number(id)
        Templates.version!(id, number)
        template.active_version = number
        template.retired_at = nil
        template.save!
        Result(TemplateView).success(Templates.view(template))
      end
    end

    # Désigne le modèle par défaut de son type de document et de sa langue
    # (D4) ; l'ancien défaut perd sa marque. Le modèle doit être actif.
    def self.set_default(actor : Actor, id : Int64) : Result(TemplateView)
      authorize!(actor, ADMIN)
      Transaction.run do
        template = Templates.lock!(id)
        if template.active_version.nil? || template.retired_at
          next Result(TemplateView).failure(FieldError.base("modeles.errors.template.not_active"))
        end
        Template.filter(kind: template.kind, locale: template.locale, is_default: true).exclude(id: id).update(is_default: false)
        template.is_default = true
        template.save!
        Result(TemplateView).success(Templates.view(template))
      end
    end

    def self.unset_default(actor : Actor, id : Int64) : Result(TemplateView)
      authorize!(actor, ADMIN)
      Transaction.run do
        template = Templates.lock!(id)
        template.is_default = false
        template.save!
        Result(TemplateView).success(Templates.view(template))
      end
    end

    # Retire un modèle : il ne sert plus et perd sa marque de défaut ; ses
    # versions et ses rendus restent consultables.
    def self.retire(actor : Actor, id : Int64) : Result(TemplateView)
      authorize!(actor, ADMIN)
      Transaction.run do
        template = Templates.lock!(id)
        next Result(TemplateView).failure(FieldError.base("modeles.errors.template.retired")) if template.retired_at
        template.retired_at = Time.utc
        template.is_default = false
        template.save!
        Result(TemplateView).success(Templates.view(template))
      end
    end

    # Fichier d'une version (tel que déposé).
    def self.version_file(actor : Actor, id : Int64, number : Int32) : FileView
      authorize!(actor, READ)
      template = Templates.find!(id)
      version = Templates.version!(id, number)
      file = Files.find!(version.file_id!.to_i64)
      FileView.new(version.filename!, Config::CONTENT_TYPES[template.format!], Files.read(file))
    end

    # Aperçu d'une version (la dernière par défaut) avec un document fictif
    # du type du modèle, dans sa langue (D3), marqué « Exemple — sans
    # valeur » ; rien n'est conservé. `pdf` : conversion demandée.
    def self.preview(actor : Actor, id : Int64, version : Int32? = nil, pdf : Bool = false) : Result(RenderView)
      authorize!(actor, READ)
      template = Templates.find!(id)
      number = version || Templates.latest_number(id)
      record = Templates.version!(id, number)
      view = Sample.document(template.kind!, template.locale!)
      marker = I18n.with_locale(template.locale!) { I18n.t("modeles.fusion.sample") }
      source = Files.read(Files.find!(record.file_id!.to_i64))
      base = "apercu-#{Templates.slug(template.name!)}-v#{number}"
      produce(template.format!, source, view, marker, base, pdf, nil)
    end

    # --- Rendus --------------------------------------------------------------------

    # Modèles utilisables pour un document : actifs, de son type ; le défaut
    # de sa langue d'abord, puis ceux de sa langue.
    def self.templates_for(actor : Actor, document_id : Int64) : Array(TemplateView)
      authorize!(actor, READ)
      document = Inv.document(actor, document_id)
      kind = Config.kind_of(document.kind) || return [] of TemplateView
      rows = Template.filter(kind: kind, active_version__isnull: false, retired_at__isnull: true).order(:name, :id).to_a
      rows.map { |row| Templates.view(row) }.sort_by! do |view|
        {view.is_default && view.locale == document.locale ? 0 : 1, view.locale == document.locale ? 0 : 1}
      end
    end

    # « Rendre avec un modèle » (ADR-010 D4) : le document (devis, facture,
    # facture d'acompte, avoir) fusionné avec la version active du modèle
    # (`template_id` ; `nil` : le modèle par défaut de son type et de sa
    # langue), au format du modèle et, si `pdf` et le convertisseur est
    # déclaré, en PDF.
    #
    # * Document émis : le rendu est conservé (fichier et PDF, empreintes
    #   SHA-256, version du modèle) ; un échec de la conversion n'empêche pas
    #   la conservation du fichier et reste noté (`pdf_error`).
    # * Brouillon : aperçu marqué « Brouillon — sans valeur », non conservé.
    #
    # La facture n'est jamais modifiée.
    def self.render(actor : Actor, document_id : Int64, template_id : Int64? = nil, pdf : Bool = true) : Result(RenderView)
      authorize!(actor, READ)
      document = Inv.document(actor, document_id)
      kind = Config.kind_of(document.kind)
      return Result(RenderView).failure(FieldError.base("modeles.errors.document.kind", {"kind" => document.kind})) unless kind
      template = if id = template_id
                   Templates.find!(id)
                 else
                   Template.filter(kind: kind, locale: document.locale, is_default: true).first
                 end
      return Result(RenderView).failure(FieldError.new("template_id", "modeles.errors.template.none")) unless template
      number = template.active_version.try(&.to_i)
      if number.nil? || template.retired_at
        return Result(RenderView).failure(FieldError.new("template_id", "modeles.errors.template.not_active"))
      end
      if template.kind != kind
        return Result(RenderView).failure(FieldError.new("template_id", "modeles.errors.template.kind_mismatch"))
      end
      version = Templates.version!(template.id!.to_i64, number)
      source = Files.read(Files.find!(version.file_id!.to_i64))
      if document.draft?
        marker = I18n.with_locale(document.locale) { I18n.t("modeles.fusion.draft") }
        return produce(template.format!, source, document, marker, "brouillon-#{document.id}", pdf, nil)
      end
      base = "#{Templates.slug(document.number.to_s)}-#{Templates.slug(template.name!)}-v#{number}"
      produce(template.format!, source, document, nil, base, pdf, {template, version, actor})
    end

    # Rendus conservés, du plus récent au plus ancien ; `document_id` : ceux
    # d'un document.
    def self.renditions(actor : Actor, document_id : Int64? = nil, limit : Int32 = 100) : Array(RenditionView)
      authorize!(actor, READ)
      rows = Rendition.all
      document_id.try { |id| rows = rows.filter(document_id: id) }
      rows.order("-created_at", "-id")[0...limit.clamp(1, MAX_LIMIT)].to_a.map { |row| Templates.rendition_view(row) }
    end

    def self.rendition(actor : Actor, id : Int64) : RenditionView
      authorize!(actor, READ)
      Templates.rendition_view(find_rendition!(id))
    end

    # Fichier d'un rendu : `file` (format du modèle) ou `pdf`.
    def self.rendition_file(actor : Actor, id : Int64, variant : String = "file") : FileView
      authorize!(actor, READ)
      rendition = find_rendition!(id)
      file_id = variant == "pdf" ? rendition.pdf_file_id : rendition.file_id
      raise Partiduo::Api::NotFound.new("modeles_rendition_file", id) if file_id.nil?
      file = Files.find!(file_id.to_i64)
      FileView.new(file.filename!, file.content_type!, Files.read(file))
    end

    # --- Convertisseurs et modèles de départ -------------------------------------

    def self.converters(actor : Actor) : Array(ConverterView)
      authorize!(actor, READ)
      FORMATS.map do |format|
        tool = Converters.tool(format)
        variable, command = Converters::VARIABLES[format]
        ConverterView.new(format, command, tool.try(&.path), (tool.try(&.timeout) || Converters.timeout).total_seconds.to_i,
          variable)
      end
    end

    # Le PDF d'un modèle de ce format peut-il être produit sur ce serveur ?
    def self.pdf_available?(actor : Actor, format : String) : Bool
      authorize!(actor, READ)
      Converters.available?(format)
    end

    # Vocabulaire du contexte de fusion, dans l'ordre de la documentation.
    def self.vocabulary(actor : Actor) : Array(VocabularyGroupView)
      authorize!(actor, READ)
      items = {"lignes" => "ligne", "tva" => "groupe", "mentions" => "mention"}
      Fusion::Vocabulary::OBJECTS.map { |name, fields| VocabularyGroupView.new(name, false, nil, fields) } +
        Fusion::Vocabulary::LISTS.map { |name, fields| VocabularyGroupView.new(name, true, items[name], fields) }
    end

    def self.starters(actor : Actor) : Array(StarterView)
      authorize!(actor, READ)
      Starters.list
    end

    def self.starter_file(actor : Actor, kind : String, locale : String, format : String) : FileView
      authorize!(actor, READ)
      unless KINDS.includes?(kind) && LOCALES.includes?(locale) && FORMATS.includes?(format)
        raise Partiduo::Api::NotFound.new("modeles_starter", 0_i64)
      end
      FileView.new(Starters.filename(kind, locale, format), Config::CONTENT_TYPES[format], Starters.file(kind, locale, format))
    end

    # Message d'une remarque de contrôle dans la langue courante (l'exigence
    # manquante est traduite : `modeles.requirements.<code>`).
    def self.message(issue : IssueView) : String
      params = issue.params.dup
      params["requirement"]?.try { |code| params["requirement"] = I18n.t("modeles.requirements.#{code}") }
      I18n.t(issue.key, params)
    end

    # --- Outils --------------------------------------------------------------------

    private def self.authorize!(actor : Actor, permission : String) : Nil
      Guard.authorize!(actor, permission, module_code: MODULE_CODE)
    end

    private def self.find_rendition!(id : Int64) : Rendition
      Rendition.filter(id: id).first || raise Partiduo::Api::NotFound.new("modeles_rendition", id)
    end

    # Fusion, conversion et, pour un document émis (`keep`), conservation.
    private def self.produce(format : String, source : Bytes, view : Inv::DocumentView, marker : String?, base : String,
                             pdf : Bool, keep : {Template, TemplateVersion, Actor}?) : Result(RenderView)
      bytes = begin
        Fusion.render(format, source, view, marker)
      rescue error : Fusion::TemplateRejected | Fusion::RenderError | Office::InvalidPackage
        return Result(RenderView).failure(FieldError.base("modeles.errors.render.failed", {"detail" => error.message.to_s}))
      end
      file = FileView.new("#{base}.#{Config::EXTENSIONS[format]}", Config::CONTENT_TYPES[format], bytes)
      pdf_file = nil
      pdf_error = nil
      pdf_detail = ""
      if pdf
        begin
          pdf_file = FileView.new("#{base}.pdf", "application/pdf", Converters.convert(format, bytes))
        rescue error : ConversionError
          pdf_error = error.key
          pdf_detail = error.detail
        end
      end
      rendition = keep.try do |(template, version, actor)|
        Transaction.run do
          Result(RenditionView).success(keep!(view, template, version, actor, file, pdf_file, pdf ? pdf_error : nil))
        end.value!
      end
      Result(RenderView).success(RenderView.new(file, pdf_file, pdf_error, pdf_detail, rendition, view.draft? || !marker.nil?))
    end

    # Conserve le rendu d'un document émis (D4).
    private def self.keep!(view : Inv::DocumentView, template : Template, version : TemplateVersion, actor : Actor,
                           file : FileView, pdf : FileView?, pdf_error : String?) : RenditionView
      stored = Files.store(file.filename, file.content_type, file.content)
      stored_pdf = pdf.try { |item| Files.store(item.filename, item.content_type, item.content) }
      rendition = Rendition.create!(
        document_id: view.id, document_kind: view.kind, document_number: view.number.to_s, locale: view.locale,
        template_id: template.id, version_id: version.id, version_number: version.number, format: template.format,
        file_id: stored.id, sha256: stored.sha256, pdf_file_id: stored_pdf.try(&.id), pdf_sha256: stored_pdf.try(&.sha256),
        pdf_error: pdf_error || "", rendered_by_id: actor.user_id,
      )
      Templates.rendition_view(rendition)
    end
  end
end
