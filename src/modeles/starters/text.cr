# SPDX-License-Identifier: AGPL-3.0-or-later

module Modeles
  module Starters
    # Modèles de départ en AsciiDoc et en Markdown.
    module Text
      def self.asciidoc(layout : Layout) : String
        t = ->(key : String) { layout.t(key) }
        String.build do |io|
          io << "= " << layout.title << "\n:nofooter:\n:lang: " << layout.locale << "\n\n"
          io << "[cols=\"1,1\",frame=none,grid=none]\n|===\n"
          io << "a|*{{ vendeur.nom }}* +\n{{ vendeur.adresse }}{% if vendeur.courriel %} +\n{{ vendeur.courriel }}{% endif %}\n"
          io << "a|*" << t.call("customer") << "* +\n{{ client.nom }} +\n{{ client.adresse }}\n|===\n\n"
          io << "[cols=\"1,2\",frame=none,grid=none,width=70%]\n|===\n"
          io << "|" << t.call("date") << " |{{ facture.date }}\n"
          layout.infos.each do |info|
            io << "{% if " << info.field << " %}|" << info.label << " |{{ " << info.field << " }}\n{% endif %}"
          end
          io << "|===\n\n"
          io << "[cols=\"6,1,1,2,1,2\",options=\"header\"]\n|===\n"
          io << "|" << t.call("description") << " >|" << t.call("quantity") << " |" << t.call("unit") << " >|"
          io << t.call("unit_price") << " >|" << t.call("vat") << " >|" << t.call("line_total") << "\n"
          io << "{% for ligne in lignes %}{% if ligne.chiffree %}|" << layout.priced_description
          io << " >|{{ ligne.quantite }} |{{ ligne.unite }} >|{{ ligne.prix_unitaire }} >|{{ ligne.taux_tva }} >|{{ ligne.montant_ht }}\n"
          io << "{% elsif ligne.sous_total %}5+|_" << layout.subtotal_description << "_ >|_{{ ligne.montant_ht }}_\n"
          io << "{% elsif ligne.note %}6+|_{{ ligne.designation }}_\n"
          io << "{% else %}6+|*{{ ligne.designation }}*\n{% endif %}{% endfor %}|===\n\n"
          io << "[cols=\"1,2,2\",options=\"header\",width=60%]\n|===\n"
          io << ">|" << t.call("vat_rate") << " >|" << t.call("vat_base") << " >|" << t.call("vat_amount") << "\n"
          io << "{% for groupe in tva %}>|{{ groupe.taux }} >|{{ groupe.base }} >|{{ groupe.montant }}\n{% endfor %}|===\n\n"
          io << "[cols=\"2,1\",frame=none,grid=rows,width=50%]\n|===\n"
          io << "|" << t.call("total_net") << " >|" << layout.amount("totaux.ht") << "\n"
          io << "|" << t.call("total_vat") << " >|" << layout.amount("totaux.tva") << "\n"
          io << "|*" << t.call("total_gross") << "* >|*" << layout.amount("totaux.ttc") << "*\n"
          io << "{% if totaux.acompte %}|" << t.call("prepaid") << " >|" << layout.amount("totaux.acompte") << "\n"
          io << "|*" << t.call("payable") << "* >|*" << layout.amount("totaux.net_a_payer") << "*\n{% endif %}|===\n\n"
          io << "{% if facture.conditions_paiement %}*" << t.call("terms") << "* {{ facture.conditions_paiement }}\n\n{% endif %}"
          if layout.invoice?
            io << "{% if reglement.iban %}*" << t.call("payment") << "* IBAN {{ reglement.iban }}{% if reglement.bic %} · BIC {{ reglement.bic }}{% endif %}"
            io << " · " << t.call("reference") << " {{ reglement.reference }}\n\n{% endif %}"
          end
          io << "{% if facture.origine %}{{ facture.origine }}\n\n{% endif %}"
          io << "{% if facture.notes %}{{ facture.notes }}\n\n{% endif %}"
          io << "." << t.call("legal") << "\n{{ mentions }}\n"
        end
      end

      def self.markdown(layout : Layout) : String
        t = ->(key : String) { layout.t(key) }
        String.build do |io|
          io << "# " << layout.title << "\n\n"
          io << "**{{ vendeur.nom }}**\\\n{{ vendeur.adresse }}{% if vendeur.courriel %}\\\n{{ vendeur.courriel }}{% endif %}\n\n"
          io << "**" << t.call("customer") << "**\\\n{{ client.nom }}\\\n{{ client.adresse }}\n\n"
          io << "| | |\n|:--|:--|\n"
          io << "| " << t.call("date") << " | {{ facture.date }} |\n"
          layout.infos.each do |info|
            io << "{% if " << info.field << " %}| " << info.label << " | {{ " << info.field << " }} |\n{% endif %}"
          end
          io << "\n"
          io << "| " << t.call("description") << " | " << t.call("quantity") << " | " << t.call("unit") << " | "
          io << t.call("unit_price") << " | " << t.call("vat") << " | " << t.call("line_total") << " |\n"
          io << "|:--|--:|:--|--:|--:|--:|\n"
          io << "{% for ligne in lignes %}{% if ligne.chiffree %}| " << layout.priced_description
          io << " | {{ ligne.quantite }} | {{ ligne.unite }} | {{ ligne.prix_unitaire }} | {{ ligne.taux_tva }} | {{ ligne.montant_ht }} |\n"
          io << "{% elsif ligne.sous_total %}| *" << layout.subtotal_description << "* | | | | | *{{ ligne.montant_ht }}* |\n"
          io << "{% elsif ligne.note %}| *{{ ligne.designation }}* | | | | | |\n"
          io << "{% else %}| **{{ ligne.designation }}** | | | | | |\n{% endif %}{% endfor %}\n"
          io << "| " << t.call("vat_rate") << " | " << t.call("vat_base") << " | " << t.call("vat_amount") << " |\n"
          io << "|--:|--:|--:|\n"
          io << "{% for groupe in tva %}| {{ groupe.taux }} | {{ groupe.base }} | {{ groupe.montant }} |\n{% endfor %}\n"
          io << "| | |\n|:--|--:|\n"
          io << "| " << t.call("total_net") << " | " << layout.amount("totaux.ht") << " |\n"
          io << "| " << t.call("total_vat") << " | " << layout.amount("totaux.tva") << " |\n"
          io << "| **" << t.call("total_gross") << "** | **" << layout.amount("totaux.ttc") << "** |\n"
          io << "{% if totaux.acompte %}| " << t.call("prepaid") << " | " << layout.amount("totaux.acompte") << " |\n"
          io << "| **" << t.call("payable") << "** | **" << layout.amount("totaux.net_a_payer") << "** |\n{% endif %}\n"
          io << "{% if facture.conditions_paiement %}**" << t.call("terms") << "** {{ facture.conditions_paiement }}\n\n{% endif %}"
          if layout.invoice?
            io << "{% if reglement.iban %}**" << t.call("payment") << "** IBAN {{ reglement.iban }}{% if reglement.bic %} · BIC {{ reglement.bic }}{% endif %}"
            io << " · " << t.call("reference") << " {{ reglement.reference }}\n\n{% endif %}"
          end
          io << "{% if facture.origine %}{{ facture.origine }}\n\n{% endif %}"
          io << "{% if facture.notes %}{{ facture.notes }}\n\n{% endif %}"
          io << "**" << t.call("legal") << "**\\\n{{ mentions }}\n"
        end
      end
    end
  end
end
