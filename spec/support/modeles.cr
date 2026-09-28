# SPDX-License-Identifier: AGPL-3.0-or-later

module Modeles
  module SpecSupport
    alias Api = Modeles::Api
    alias Inv = Partiduo::Api::Invoicing
    alias Books = PartiduoUi::Books

    SYSTEM = Partiduo::Api::Actor.system
    READER = [Api::READ, "invoicing.invoice.read"]
    ADMIN  = [Api::READ, Api::ADMIN, "invoicing.invoice.read"]
    BIN    = File.join(ROOT, "spec", "support", "bin")

    @@user_id = 1_i64

    def self.actor(permissions : Array(String) = ADMIN) : Partiduo::Api::Actor
      Partiduo::Api::Actor.user(@@user_id, permissions, level: 3)
    end

    def self.reader : Partiduo::Api::Actor
      actor(READER)
    end

    def self.d(text : String) : BigDecimal
      BigDecimal.new(text)
    end

    # Dossier français, administrateur, Facturation paramétrée (IBAN, BIC),
    # extension MODELES active.
    def self.books(activate : Bool = true) : Nil
      PartiduoUi::Reference.provision("fr")
      @@user_id = PartiduoUi::Accounts.create.user.id
      settings = Inv.settings(SYSTEM)
      Inv.update_settings(SYSTEM, settings.to_input.copy_with(iban: "FR7630006000011234567890189", bic: "AGRIFRPP")).value!
      Partiduo::Api::Modules.activate(SYSTEM, CODE).value! if activate
      nil
    end

    def self.customer(name : String = "Durand & Fils <SARL>", locale : String? = nil) : Partiduo::Api::Cards::CardView
      category = PartiduoUi::Reference.category("CUSTOMER")
      input = Partiduo::Api::Cards::CardInput.new(category_id: category.id, name: name, siren: "552100554",
        customer_nature: "business", email: "compta@durand.test",
        address: Partiduo::Api::Cards::AddressInput.new(line1: "3 rue du Port", line2: "Bâtiment *B*", postcode: "13002",
          city: "Marseille", country_code: "FR"))
      Partiduo::Api::Cards.create_card(SYSTEM, input).value!
    end

    def self.item : Partiduo::Api::Cards::CardView
      Partiduo::Api::Cards.card_by_code(SYSTEM, "CONSEIL") || begin
        rate = Partiduo::Api::Vat.rate_by_code(SYSTEM, "NOR") || raise "taux NOR absent"
        Partiduo::Api::Cards.create_card(SYSTEM, Partiduo::Api::Cards::CardInput.new(
          category_id: PartiduoUi::Reference.category("SALE").id, name: "Conseil", code: "CONSEIL", unit_code: "HUR",
          sale_price: d("80"), vat_rate_id: rate.id)).value!
      end
    end

    def self.draft(kind : String = "invoice", locale : String? = nil, customer_id : Int64? = nil,
                   credited : Int64? = nil) : Inv::DocumentView
      lines = [
        Inv::LineInput.new(kind: "title", description: "Mission d'audit"),
        Inv::LineInput.new(item_card_id: item.id, quantity: d("10"), description: "Conseil *urgent* | analyse\nsur site"),
        Inv::LineInput.new(item_card_id: item.id, quantity: d("2.5"), discount_kind: "percent", discount_value: d("10")),
      ]
      Inv.create_document(SYSTEM, Inv::DocumentInput.new(kind: kind, customer_card_id: customer_id || customer.id, lines: lines,
        buyer_reference: "BC-42", locale: locale, credited_document_id: credited)).value!
    end

    def self.issue(kind : String = "invoice", locale : String? = nil, credited : Int64? = nil,
                   customer_id : Int64? = nil) : Inv::DocumentView
      Inv.issue(SYSTEM, draft(kind, locale, customer_id, credited).id, Inv::IssueInput.new(Books.date("2026-09-15"))).value!
    end

    # Dépose un modèle (un modèle de départ par défaut) et l'active.
    def self.template(kind : String = "invoice", locale : String = "fr", format : String = "markdown",
                      content : Bytes? = nil, name : String = "Modèle #{format}", default : Bool = true) : Api::TemplateView
      bytes = content || Modeles::Starters.file(kind, locale, format)
      filename = "modele.#{Modeles::Config::EXTENSIONS[format]}"
      view = Api.upload(actor, Api::UploadInput.new(filename: filename, content: bytes, name: name, kind: kind,
        locale: locale)).value!
      Api.activate(actor, view.id).value!
      default ? Api.set_default(actor, view.id).value! : Api.template(actor, view.id)
    end

    def self.fake_tool(script : String = "fake-convert", timeout : Time::Span = 10.seconds) : Modeles::Converters::Tool
      Modeles::Converters::Tool.new(script, File.join(BIN, script), timeout)
    end

    # Convertisseurs de substitution pour les quatre formats.
    def self.fake_converters(script : String = "fake-convert", timeout : Time::Span = 10.seconds) : Nil
      Modeles::Config::FORMATS.each { |format| Modeles::Converters.override(format, fake_tool(script, timeout)) }
    end

    def self.text(bytes : Bytes) : String
      String.new(bytes)
    end
  end
end

# Chaque exemple part sans convertisseur (l'environnement n'en déclare
# aucun) : les specs qui en ont besoin les fixent.
Spec.before_each do
  Modeles::Converters.reset
  Modeles::Config::FORMATS.each { |format| Modeles::Converters.override(format, nil) }
end
