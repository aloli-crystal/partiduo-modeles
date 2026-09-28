# SPDX-License-Identifier: AGPL-3.0-or-later

module Modeles
  # Règles des modèles, versions et rendus (interne ; appelées par
  # `Modeles::Api`).
  module Templates
    alias FieldError = Partiduo::Api::FieldError

    MAX_NAME = 120

    def self.find!(id : Int64) : Template
      Template.filter(id: id).first || raise Partiduo::Api::NotFound.new("modeles_template", id)
    end

    def self.lock!(id : Int64) : Template
      Template.all.lock.filter(id: id).first || raise Partiduo::Api::NotFound.new("modeles_template", id)
    end

    def self.version!(template_id : Int64, number : Int32) : TemplateVersion
      TemplateVersion.filter(template_id: template_id, number: number).first ||
        raise Partiduo::Api::NotFound.new("modeles_template_version", number.to_i64)
    end

    def self.latest_number(template_id : Int64) : Int32
      TemplateVersion.filter(template_id: template_id).order("-number").first.try(&.number!.to_i) || 0
    end

    # Contrôle d'un fichier déposé : format (extension), taille, analyse
    # (syntaxe, champs, mentions obligatoires du type `kind`).
    def self.check(filename : String, content : Bytes, kind : String?, expected_format : String? = nil) : Api::CheckView
      format = Config.format_of(filename)
      errors = [] of Api::IssueView
      warnings = [] of Api::IssueView
      fields = [] of String
      if format.nil?
        errors << issue("format_unknown", {"filename" => filename})
      elsif expected_format && format != expected_format
        errors << issue("format_changed", {"expected" => expected_format.upcase, "format" => format.upcase})
      elsif content.empty?
        errors << issue("empty")
      elsif content.size > Config::MAX_BYTES
        errors << issue("too_large", {"max" => (Config::MAX_BYTES // (1024 * 1024)).to_s})
      else
        report = Fusion.analyze(format, content, kind.presence.try { |value| Config::KINDS.includes?(value) ? value : nil })
        report.errors.each { |item| errors << issue(item.code, item.params) }
        report.warnings.each { |item| warnings << issue(item.code, item.params) }
        fields = (report.printed.to_a + report.referenced.to_a).uniq!.sort!
        warnings << issue("no_pdf", {"format" => format.upcase}) unless Converters.available?(format)
      end
      Api::CheckView.new(format, errors, warnings, fields, format ? Converters.available?(format) : false)
    end

    def self.issue(code : String, params = {} of String => String) : Api::IssueView
      Api::IssueView.new("modeles.check.#{code}", params)
    end

    # Erreurs des champs d'un nouveau modèle (nom, type, langue).
    def self.field_errors(input : Api::UploadInput) : Array(FieldError)
      errors = [] of FieldError
      name = input.name.strip
      if name.empty?
        errors << FieldError.new("name", "modeles.errors.name.blank")
      elsif name.size > MAX_NAME
        errors << FieldError.new("name", "modeles.errors.name.too_long", {"max" => MAX_NAME.to_s})
      end
      unless Config::KINDS.includes?(input.kind)
        errors << FieldError.new("kind", "modeles.errors.kind.invalid", {"value" => input.kind})
      end
      unless Config::LOCALES.includes?(input.locale)
        errors << FieldError.new("locale", "modeles.errors.locale.invalid", {"value" => input.locale})
      end
      errors
    end

    def self.version_view(version : TemplateVersion) : Api::VersionView
      warnings = begin
        JSON.parse(version.warnings || "[]").as_a.map do |item|
          Api::IssueView.new(item["key"].as_s, item["params"].as_h.transform_values(&.as_s))
        end
      rescue JSON::ParseException | TypeCastError | KeyError
        [] of Api::IssueView
      end
      Api::VersionView.new(
        id: version.id!.to_i64, template_id: version.template_id!.to_i64, number: version.number!.to_i,
        filename: version.filename!, byte_size: version.byte_size!.to_i64, sha256: version.sha256!,
        warnings: warnings, uploaded_by_id: version.uploaded_by_id.try(&.to_i64), created_at: version.created_at!,
      )
    end

    def self.view(template : Template) : Api::TemplateView
      versions = TemplateVersion.filter(template_id: template.id).order("-number").to_a.map { |version| version_view(version) }
      Api::TemplateView.new(
        id: template.id!.to_i64, name: template.name!, kind: template.kind!, locale: template.locale!,
        format: template.format!, active_version: template.active_version.try(&.to_i),
        latest_version: versions.first?.try(&.number) || 0, is_default: template.is_default!,
        retired_at: template.retired_at, created_at: template.created_at!, updated_at: template.updated_at!,
        versions: versions,
      )
    end

    def self.warnings_json(warnings : Array(Api::IssueView)) : String
      warnings.map { |item| {"key" => item.key, "params" => item.params} }.to_json
    end

    # Nom de fichier sûr et lisible : lettres, chiffres, tirets.
    def self.slug(text : String) : String
      text.unicode_normalize(:nfkd).gsub(/[^\x00-\x7F]/, "").downcase.gsub(/[^a-z0-9]+/, "-").strip('-').presence || "modele"
    end

    def self.rendition_view(rendition : Rendition) : Api::RenditionView
      file = Files.find!(rendition.file_id!.to_i64)
      pdf = rendition.pdf_file_id.try { |id| Files.find!(id.to_i64) }
      template = Template.filter(id: rendition.template_id).first
      Api::RenditionView.new(
        id: rendition.id!.to_i64, document_id: rendition.document_id!.to_i64, document_kind: rendition.document_kind!,
        document_number: rendition.document_number!, locale: rendition.locale!,
        template_id: rendition.template_id!.to_i64, template_name: template.try(&.name) || "",
        version_id: rendition.version_id!.to_i64, version_number: rendition.version_number!.to_i, format: rendition.format!,
        filename: file.filename!, sha256: rendition.sha256!, byte_size: file.byte_size!.to_i64,
        pdf_filename: pdf.try(&.filename), pdf_sha256: rendition.pdf_sha256, pdf_error: rendition.pdf_error || "",
        rendered_by_id: rendition.rendered_by_id.try(&.to_i64), created_at: rendition.created_at!,
      )
    end
  end
end
