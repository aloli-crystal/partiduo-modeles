# SPDX-License-Identifier: AGPL-3.0-or-later

module Modeles
  # Document fictif de l'aperçu d'un modèle (ADR-010 D3) : une facture, un
  # devis ou un avoir complet (deux lignes, un titre, une remise, deux taux
  # de TVA, mentions légales), dans la langue voulue. Il ne touche pas la
  # Facturation : c'est une vue construite de toutes pièces.
  module Sample
    alias Inv = Partiduo::Api::Invoicing

    NUMBERS = {"invoice" => "F-EXEMPLE-0001", "quote" => "D-EXEMPLE-0001", "credit_note" => "A-EXEMPLE-0001"}

    def self.d(text : String) : BigDecimal
      BigDecimal.new(text)
    end

    def self.document(kind : String, locale : String, today : Time = Partiduo::Api::Core.today) : Inv::DocumentView
      issue = Time.utc(today.year, today.month, today.day)
      due = issue + 30.days
      seller = Inv::PartyView.new(name: "Atelier Exemple SARL", code: "", legal_form: "SARL", share_capital: d("10000"),
        rcs: "RCS Lyon 123 456 789", siren: "123456789", siret: "12345678900012", vat_number: "FR32123456789",
        line1: "12 rue des Artisans", line2: "", postcode: "69001", city: "Lyon", country_code: "FR",
        email: "contact@exemple.test", phone: "04 00 00 00 00", routing_id: "", nature: "business")
      customer = Inv::PartyView.new(name: "Client Modèle & Fils", code: "C-0001", legal_form: "SAS", share_capital: nil,
        rcs: "", siren: "987654321", siret: "98765432100018", vat_number: "FR06987654321",
        line1: "3 avenue du Commerce", line2: "Bâtiment B", postcode: "75011", city: "Paris", country_code: "FR",
        email: "compta@client.test", phone: "", routing_id: "", nature: "business")
      lines = [
        line(1, "title", "Prestations", "0", "0", "0", "0"),
        line(2, "item", "Conseil en organisation\nAtelier d'une demi-journée", "3", "450", "20", "1350"),
        line(3, "free", "Frais de déplacement", "1", "80", "20", "80", discount: "10"),
        line(4, "item", "Livre « Bien facturer »", "2", "25", "5.5", "50"),
      ]
      breakdown = [
        Inv::VatBreakdownView.new("S", d("20"), "", "", d("1422"), d("0"), d("1422"), d("284.40")),
        Inv::VatBreakdownView.new("S", d("5.5"), "", "", d("50"), d("0"), d("50"), d("2.75")),
      ]
      totals = Inv::TotalsView.new(lines_total: d("1480"), discount_total: d("8"), total_net: d("1472"),
        total_vat: d("287.15"), total_gross: d("1759.15"), prepaid: d("0"), paid: d("0"), credited: d("0"))
      credited = kind == "credit_note" ? Inv::LinkView.new(0_i64, "invoice", "F-EXEMPLE-0000", "issued") : nil
      Inv::DocumentView.new(
        id: 0_i64, kind: kind, status: "issued", effective_status: "issued", series: "", number: NUMBERS[kind]? || NUMBERS["invoice"],
        customer_card_id: 0_i64, customer: customer, seller: seller, source: nil, derived: [] of Inv::LinkView,
        credited: credited, credit_notes: [] of Inv::LinkView, locale: locale, currency_code: "EUR",
        issue_date: issue, delivery_date: issue, due_date: kind == "invoice" ? due : nil,
        validity_date: kind == "quote" ? due : nil, operation_category: "services", vat_on_debits: false,
        buyer_reference: "BC-2026-042", order_reference: "CMD-17", notes: "",
        global_discount_kind: "none", global_discount_value: d("0"), delivery_address: nil, structured_reference: "",
        lines: lines, vat_breakdown: breakdown, totals: totals, deductions: [] of Inv::DeductionView,
        mentions: mentions(kind, issue, due), layout_id: nil, issued_at: issue, issued_by_id: nil,
        fingerprint: "0" * 64, pdf_attachment_id: nil, sent_at: nil, created_at: issue, updated_at: issue,
      )
    end

    private def self.line(position : Int32, kind : String, description : String, quantity : String, price : String,
                          vat : String, net : String, discount : String? = nil) : Inv::LineView
      discount_amount = discount ? d(price) * d(quantity) * d(discount) / d("100") : d("0")
      Inv::LineView.new(position: position, kind: kind, item_card_id: nil, description: description,
        quantity: d(quantity), unit_code: kind == "item" && position == 2 ? "HUR" : "C62", unit_price: d(price),
        discount_kind: discount ? "percent" : "none", discount_value: discount ? d(discount) : d("0"),
        discount_amount: discount_amount, gross_amount: d(price) * d(quantity), vat_rate_id: nil,
        vat_percent: d(vat), vat_category: kind == "title" ? "" : "S", net_amount: d(net) - discount_amount)
    end

    private def self.mentions(kind : String, issue : Time, due : Time) : Array(Inv::MentionView)
      iso = ->(time : Time) { time.to_s("%Y-%m-%d") }
      list = [
        mention("seller.legal_form_capital", {"legal_form" => "SARL", "capital" => "10000", "currency" => "EUR"}),
        mention("seller.rcs.fr", {"rcs" => "RCS Lyon 123 456 789"}),
        mention("seller.siren", {"siren" => "123456789"}),
        mention("seller.vat_number", {"vat_number" => "FR32123456789"}),
        mention("customer.siren", {"siren" => "987654321"}),
        mention("customer.vat_number", {"vat_number" => "FR06987654321"}),
        mention("dates.issue", {"date" => iso.call(issue)}),
      ]
      case kind
      when "quote"
        list << mention("quote.validity", {"date" => iso.call(due)})
      when "credit_note"
        list << mention("operation_category.services")
        list << mention("credit_note.reference", {"number" => "F-EXEMPLE-0000", "date" => iso.call(issue - 10.days)})
      else
        list << mention("dates.delivery", {"date" => iso.call(issue)})
        list << mention("operation_category.services")
        list << mention("dates.due", {"date" => iso.call(due)})
        list << mention("payment.bank", {"iban" => "FR76 3000 6000 0112 3456 7890 189", "bic" => "AGRIFRPP"})
        list << mention("payment.no_early_discount")
        list << mention("payment.late_penalties_legal.fr")
        list << mention("payment.indemnity", {"amount" => "40.00", "currency" => "EUR"})
      end
      list
    end

    private def self.mention(code : String, params = {} of String => String) : Inv::MentionView
      Inv::MentionView.new(code, "invoicing.mentions.#{code}", params)
    end
  end
end
