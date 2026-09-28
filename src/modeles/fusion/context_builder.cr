# SPDX-License-Identifier: AGPL-3.0-or-later

module Modeles
  module Fusion
    # Contexte de fusion d'un document de la Facturation (ADR-010 D2), bâti
    # depuis sa vue publique (`Partiduo::Api::Invoicing::DocumentView`) :
    # vocabulaire de `Vocabulary`, valeurs présentées dans la langue du
    # document et échappées selon le format du modèle.
    #
    # `marker` : mention d'un rendu sans valeur (brouillon, facture fictive
    # de l'aperçu) ; elle remplace le numéro absent et `facture.brouillon`
    # est vrai.
    class ContextBuilder
      alias Inv = Partiduo::Api::Invoicing
      alias Value = Record::Value

      getter fmt : Formatter

      def initialize(@view : Inv::DocumentView, @format : String, @marker : String? = nil)
        @fmt = Formatter.new(@view.locale.in?(Config::LOCALES) ? @view.locale : "fr")
      end

      def locale : String
        fmt.locale
      end

      # Valeurs de premier niveau du contexte, pour `Marten::Template::Context`.
      def build : Hash(String, Marten::Template::Value)
        I18n.with_locale(locale) do
          {
            "facture"   => document,
            "vendeur"   => party(@view.seller),
            "client"    => customer,
            "lignes"    => lines,
            "tva"       => vat,
            "totaux"    => totals,
            "reglement" => payment,
            "mentions"  => mentions,
          }.transform_values { |value| Marten::Template::Value.from(value) }
        end
      end

      # Texte des mentions légales dans la langue du document, dates et
      # montants présentés comme dans le PDF légal.
      def mention_texts : Array(String)
        I18n.with_locale(locale) { @view.mentions.map { |mention| mention_text(mention) } }
      end

      # Valeur présentée et échappée ; une valeur vide devient `nil`, fausse
      # dans un `{% if %}` et remplacée par le filtre `default`.
      private def s(value : String, inline : Bool = false) : String?
        value.strip.empty? ? nil : Escaper.escape(@format, value, inline)
      end

      private def document : Record
        view = @view
        number = view.number || @marker || ""
        credited = view.credited
        Record.new({
          "numero"               => s(number),
          "type"                 => s(I18n.t(view.kind_key)),
          "nature"               => view.kind,
          "code_type"            => view.type_code,
          "date"                 => s(fmt.date(view.issue_date)),
          "date_livraison"       => s(fmt.date(view.delivery_date)),
          "echeance"             => s(fmt.date(view.due_date)),
          "validite"             => s(fmt.date(view.validity_date)),
          "devise"               => s(view.currency_code),
          "reference_acheteur"   => s(view.buyer_reference),
          "reference_commande"   => s(view.order_reference),
          "reference_paiement"   => s(view.structured_reference.presence || view.number || ""),
          "conditions_paiement"  => s(terms),
          "categorie_operation"  => s(I18n.t("modeles.fusion.categories.#{view.operation_category}")),
          "remise_globale"       => s(global_discount),
          "notes"                => s(view.notes),
          "origine"              => s(view.origin_mention.try { |mention| mention_text(mention) } || ""),
          "facture_origine"      => s(credited.try(&.number) || ""),
          "facture_origine_date" => s(credited_date),
          "langue"               => locale,
          "brouillon"            => view.draft? || !@marker.nil?,
          "empreinte"            => view.fingerprint.presence,
        } of String => Value)
      end

      private def party(party : Inv::PartyView) : Record
        Record.new({
          "nom"             => s(party.name),
          "code"            => s(party.code),
          "forme_juridique" => s(party.legal_form),
          "capital"         => s(party.share_capital.try { |capital| fmt.amount(capital) } || ""),
          "rcs"             => s(party.rcs),
          "siren"           => s(party.siren),
          "siret"           => s(party.siret),
          "tva"             => s(party.vat_number),
          "adresse"         => s(party.address_lines.join('\n')),
          "adresse_ligne1"  => s(party.line1),
          "adresse_ligne2"  => s(party.line2),
          "code_postal"     => s(party.postcode),
          "ville"           => s(party.city),
          "pays"            => s(party.country_code),
          "courriel"        => s(party.email),
          "telephone"       => s(party.phone),
        } of String => Value)
      end

      private def customer : Record
        record = party(@view.customer)
        record["adresse_livraison"] = s(@view.delivery_address.try(&.lines.join('\n')) || "")
        record["professionnel"] = @view.customer.professional?
        record
      end

      private def lines : Array(Record)
        @view.lines.map do |line|
          priced = line.priced?
          Record.new({
            "numero"        => line.position.to_s,
            "nature"        => line.kind,
            "designation"   => s(line.description, inline: true),
            "quantite"      => priced ? s(fmt.quantity(line.quantity)) : "",
            "unite"         => priced ? s(unit(line.unit_code), inline: true) : "",
            "prix_unitaire" => priced ? s(fmt.amount(line.unit_price)) : "",
            "remise"        => priced ? s(discount(line)) : "",
            "taux_tva"      => priced ? s(fmt.percent(line.vat_percent)) : "",
            "montant_ht"    => priced || line.kind == "subtotal" ? s(fmt.amount(line.net_amount)) : "",
            "chiffree"      => priced,
            "titre"         => line.kind == "title",
            "note"          => line.kind == "note",
            "sous_total"    => line.kind == "subtotal",
          } of String => Value)
        end
      end

      private def vat : Array(Record)
        @view.vat_breakdown.map do |group|
          Record.new({
            "taux"      => s(fmt.percent(group.percent)),
            "base"      => s(fmt.amount(group.base)),
            "montant"   => s(fmt.amount(group.vat)),
            "categorie" => group.category.presence,
            "motif"     => s(group.exemption_reason, inline: true),
          } of String => Value)
        end
      end

      private def totals : Record
        totals = @view.totals
        Record.new({
          "lignes_ht"   => s(fmt.amount(totals.lines_total)),
          "remise"      => s(totals.discount_total.zero? ? "" : fmt.amount(totals.discount_total)),
          "ht"          => s(fmt.amount(totals.total_net)),
          "tva"         => s(fmt.amount(totals.total_vat)),
          "ttc"         => s(fmt.amount(totals.total_gross)),
          "acompte"     => s(totals.prepaid.zero? ? "" : fmt.amount(totals.prepaid)),
          "net_a_payer" => s(fmt.amount(totals.payable)),
        } of String => Value)
      end

      # Coordonnées bancaires : celles de la mention de règlement calculée
      # par le cœur (paramètres de la Facturation à l'émission).
      private def payment : Record
        bank = @view.mentions.find { |mention| mention.code == "payment.bank" }
        Record.new({
          "iban"      => s(bank.try(&.params["iban"]?) || ""),
          "bic"       => s(bank.try(&.params["bic"]?) || ""),
          "reference" => s(@view.structured_reference.presence || @view.number || ""),
          "titulaire" => s(@view.seller.name),
          "echeance"  => s(fmt.date(@view.due_date)),
        } of String => Value)
      end

      private def mentions : Block
        texts = mention_texts
        items = @view.mentions.zip(texts).map do |mention, text|
          Record.new({"code" => mention.code, "texte" => s(text)} of String => Value)
        end
        Block.new(items, texts.compact_map { |text| s(text) }.join(block_separator))
      end

      # Séparateur des mentions de `{{ mentions }}` : une mention par ligne.
      private def block_separator : String
        case @format
        when "asciidoc" then " +\n"
        when "markdown" then "\\\n"
        else                 Escaper::NEWLINE.to_s
        end
      end

      # Conditions de paiement : à réception, ou à N jours avec l'échéance ;
      # validité d'un devis.
      private def terms : String
        view = @view
        if view.kind == "quote"
          view.validity_date.try { |date| I18n.t("modeles.fusion.terms.quote", date: fmt.date(date)) } || ""
        elsif view.kind == "credit_note"
          ""
        elsif (due = view.due_date) && (issued = view.issue_date)
          days = (due - issued).days
          days <= 0 ? I18n.t("modeles.fusion.terms.on_receipt") : I18n.t("modeles.fusion.terms.days", count: days, date: fmt.date(due))
        else
          ""
        end
      end

      private def global_discount : String
        case @view.global_discount_kind
        when "percent" then fmt.percent(@view.global_discount_value)
        when "amount"  then fmt.amount(@view.global_discount_value)
        else                ""
        end
      end

      private def discount(line : Inv::LineView) : String
        case line.discount_kind
        when "percent" then fmt.percent(line.discount_value)
        when "amount"  then fmt.amount(line.discount_value)
        else                ""
        end
      end

      # Libellé d'une unité UN/ECE (recommandation n° 20) : les plus
      # courantes sont traduites, les autres gardent leur code.
      private def unit(code : String) : String
        key = "modeles.fusion.units.#{code.downcase}"
        label = I18n.t(key)
        label.includes?("missing") ? code : label
      end

      private def credited_date : String
        @view.mentions.find { |mention| mention.code == "credit_note.reference" }
          .try(&.params["date"]?).try { |iso| iso_date(iso) } || ""
      end

      private def iso_date(value : String) : String
        return value unless value.matches?(/\A\d{4}-\d{2}-\d{2}\z/)
        fmt.date(Time.parse_utc(value, "%Y-%m-%d"))
      end

      # Texte d'une mention (paramètres présentés comme dans le PDF légal).
      private def mention_text(mention : Inv::MentionView) : String
        params = mention.params.to_h do |key, value|
          formatted = if key == "date"
                        iso_date(value)
                      elsif key.in?("amount", "capital") && (number = BigDecimal.new(value) rescue nil)
                        fmt.amount(number)
                      elsif key == "rate" && (number = BigDecimal.new(value) rescue nil)
                        fmt.quantity(number)
                      elsif key == "currency"
                        value == "EUR" ? "€" : value
                      else
                        value
                      end
          {key, formatted}
        end
        I18n.t(mention.key, params)
      end
    end
  end
end
