# SPDX-License-Identifier: AGPL-3.0-or-later

module Modeles
  # Modèles de départ (ADR-010 D6) : facture, devis et avoir, en AsciiDoc,
  # Markdown, ODT et DOCX, en français, en anglais et en néerlandais,
  # complets et conformes (ils passent le contrôle du dépôt). Ils sont
  # produits par le code, libellés tirés des traductions
  # (`modeles.starters.*`) : l'utilisateur les télécharge, les adapte dans
  # son logiciel et les redépose. `scripts/starters.cr` les écrit dans
  # `starters/` pour les lire sans lancer Partiduo (archives ODT et DOCX
  # identiques d'une génération à l'autre).
  module Starters
    NAMES = {"invoice" => "facture", "quote" => "devis", "credit_note" => "avoir"}

    def self.list : Array(Api::StarterView)
      Config::KINDS.flat_map do |kind|
        Config::LOCALES.flat_map do |locale|
          Config::FORMATS.map { |format| Api::StarterView.new(kind, locale, format, filename(kind, locale, format)) }
        end
      end
    end

    def self.filename(kind : String, locale : String, format : String) : String
      "modele-#{NAMES[kind]}-#{locale}.#{Config::EXTENSIONS[format]}"
    end

    def self.file(kind : String, locale : String, format : String) : Bytes
      layout = Layout.new(kind, locale)
      case format
      when "asciidoc" then Text.asciidoc(layout).to_slice
      when "markdown" then Text.markdown(layout).to_slice
      when "odt"      then OdtBuilder.new(layout).build
      when "docx"     then DocxBuilder.new(layout).build
      else                 raise ArgumentError.new("format inconnu : #{format}")
      end
    end

    # Contenu d'un modèle de départ, commun aux quatre formats : libellés
    # dans la langue du modèle et lignes d'information selon le type.
    class Layout
      getter kind : String
      getter locale : String

      # Ligne d'information : libellé et champ imprimé (s'il est renseigné).
      record Info, label : String, field : String

      def initialize(@kind : String, @locale : String)
      end

      def t(key : String) : String
        I18n.with_locale(locale) { I18n.t("modeles.starters.#{key}") }
      end

      def title : String
        "{{ facture.type }} {{ facture.numero }}"
      end

      # Lignes d'information sous l'en-tête ; la date est toujours imprimée.
      def infos : Array(Info)
        list = [] of Info
        case kind
        when "quote"
          list << Info.new(t("validity"), "facture.validite")
        when "credit_note"
          list << Info.new(t("credited"), "facture.facture_origine")
          list << Info.new(t("credited_date"), "facture.facture_origine_date")
        else
          list << Info.new(t("delivery_date"), "facture.date_livraison")
          list << Info.new(t("due_date"), "facture.echeance")
        end
        list << Info.new(t("buyer_reference"), "facture.reference_acheteur")
        list << Info.new(t("order_reference"), "facture.reference_commande")
        list
      end

      def invoice? : Bool
        kind == "invoice"
      end

      # Désignation d'une ligne chiffrée, avec sa remise.
      def priced_description : String
        %({{ ligne.designation }}{% if ligne.remise %} (#{t("discount")} {{ ligne.remise }}){% endif %})
      end

      def subtotal_description : String
        %({{ ligne.designation|default:"#{t("subtotal")}" }})
      end

      def amount(field : String) : String
        "{{ #{field} }} {{ facture.devise }}"
      end
    end
  end
end
