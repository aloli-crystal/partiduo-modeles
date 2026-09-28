# SPDX-License-Identifier: AGPL-3.0-or-later

module Modeles
  module Ui
    # Base des écrans de l'extension. L'accès a déjà été contrôlé par
    # `PartiduoUi::ExtensionHandler` à partir du manifeste ; `Modeles::Api`
    # vérifie encore la permission de chaque commande.
    abstract class Handler < PartiduoUi::ScreenHandler
      alias Api = Modeles::Api
      alias Inv = Partiduo::Api::Invoicing

      def can_admin? : Bool
        can?(Api::ADMIN)
      end

      def crumbs(title : String? = nil, middle : PartiduoUi::Screen::Crumb? = nil) : Array(PartiduoUi::Screen::Crumb)
        list = [crumb("invoicing.menu.inv_documents"), crumb("modeles.menu.templates", title ? Ui.url("index") : nil)]
        middle.try { |item| list << item }
        list << PartiduoUi::Screen::Crumb.new(title) if title
        list
      end

      def messages(result) : String
        result.errors.map { |error| fmt.message(error) }.join(" ")
      end

      def choices(values : Array(String), selected : String, prefix : String) : Array(Row)
        values.map do |value|
          Ui.row({"value" => value, "label" => I18n.t("#{prefix}.#{value}"), "selected" => Ui.flag(value == selected)})
        end
      end

      # Fichier déposé par un formulaire `multipart/form-data`.
      def upload(name : String = "file") : {String, Bytes}?
        file = request.data.fetch(name, nil).as?(Marten::HTTP::UploadedFile) || return
        io = file.io
        io.rewind
        {file.filename || "", io.getb_to_end}
      ensure
        file.try { |item| item.io.delete rescue nil }
      end

      # Erreurs d'un dépôt refusé, par champ du formulaire (`content` →
      # `file`).
      def upload_errors(errors : Array(Partiduo::Api::FieldError)) : {Hash(String, Array(String)), Array(String)}
        fields = {} of String => Array(String)
        report = [] of String
        errors.each do |error|
          message = I18n.t(error.key, error.params.to_h { |key, value| {key, key == "requirement" ? I18n.t("modeles.requirements.#{value}") : value} })
          case error.field
          when "content"                then report << message
          when "name", "kind", "locale" then (fields[error.field] ||= [] of String) << message
          else                               (fields["base"] ||= [] of String) << message
          end
        end
        {fields, report}
      end
    end
  end
end
