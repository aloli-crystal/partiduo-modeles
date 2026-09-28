# SPDX-License-Identifier: AGPL-3.0-or-later

module Modeles
  module SpecSupport
    # Vrais fichiers ODT et DOCX construits dans les specs, avec des champs
    # coupés en plusieurs fragments de mise en forme comme les produit un
    # traitement de texte.
    module OfficeFiles
      W  = %(xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main")
      NS = Modeles::Starters::OdtBuilder::NAMESPACES

      # --- DOCX ------------------------------------------------------------------

      # Fragment de texte (`<w:r>`), gras au besoin.
      def self.r(text : String, bold : Bool = false) : String
        %(<w:r>#{bold ? "<w:rPr><w:b/></w:rPr>" : ""}<w:t>#{text}</w:t></w:r>)
      end

      def self.para(*runs : String) : String
        "<w:p>#{runs.join}</w:p>"
      end

      def self.tr(*cells : String) : String
        "<w:tr>" + cells.map { |cell| "<w:tc><w:tcPr><w:tcW w:w=\"2000\" w:type=\"dxa\"/></w:tcPr>#{cell}</w:tc>" }.join + "</w:tr>"
      end

      def self.tbl(*rows : String) : String
        "<w:tbl><w:tblPr/><w:tblGrid/>#{rows.join}</w:tbl>"
      end

      def self.docx(body : String, header : String? = nil) : Bytes
        package = Modeles::Office::Package.new
        package["[Content_Types].xml"] = %(<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>)
        package["_rels/.rels"] = %(<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>)
        package["word/document.xml"] = %(<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<w:document #{W}><w:body>#{body}<w:sectPr/></w:body></w:document>)
        header.try { |xml| package["word/header1.xml"] = %(<?xml version="1.0" encoding="UTF-8"?><w:hdr #{W}>#{xml}</w:hdr>) }
        package.to_bytes
      end

      # --- ODT -------------------------------------------------------------------

      def self.span(text : String) : String
        %(<text:span text:style-name="T1">#{text}</text:span>)
      end

      def self.tp(*parts : String) : String
        %(<text:p text:style-name="P1">#{parts.join}</text:p>)
      end

      def self.row(*cells : String) : String
        "<table:table-row>" + cells.map { |cell| %(<table:table-cell office:value-type="string">#{cell}</table:table-cell>) }.join + "</table:table-row>"
      end

      def self.table(*rows : String) : String
        %(<table:table table:name="T"><table:table-column table:number-columns-repeated="3"/>#{rows.join}</table:table>)
      end

      def self.odt(body : String, footer : String? = nil) : Bytes
        package = Modeles::Office::Package.new
        package["mimetype"] = Modeles::Office::Odt::MIMETYPE
        package["META-INF/manifest.xml"] = %(<?xml version="1.0" encoding="UTF-8"?><manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0" manifest:version="1.3"><manifest:file-entry manifest:full-path="/" manifest:media-type="application/vnd.oasis.opendocument.text"/><manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/><manifest:file-entry manifest:full-path="styles.xml" manifest:media-type="text/xml"/></manifest:manifest>)
        package["content.xml"] = %(<?xml version="1.0" encoding="UTF-8"?>\n<office:document-content #{NS}><office:body><office:text><text:sequence-decls/>#{body}</office:text></office:body></office:document-content>)
        master = footer ? %(<style:master-page style:name="Standard"><style:footer>#{footer}</style:footer></style:master-page>) : ""
        package["styles.xml"] = %(<?xml version="1.0" encoding="UTF-8"?>\n<office:document-styles #{NS}><office:master-styles>#{master}</office:master-styles></office:document-styles>)
        package.to_bytes
      end

      # --- Lecture ---------------------------------------------------------------

      def self.part(bytes : Bytes, name : String) : String
        Modeles::Office::Package.read(bytes).text(name) || raise "partie #{name} absente"
      end

      # Texte visible d'un XML (balises retirées, entités décodées).
      def self.visible(xml : String) : String
        HTML.unescape(xml.gsub(/<text:line-break\/>|<w:br\/>/, "\n").gsub(/<[^>]+>/, ""))
      end

      # Champs obligatoires d'une facture, écrits dans un DOCX dont plusieurs
      # champs sont coupés en fragments (correcteur d'orthographe, gras).
      def self.invoice_docx(extra : String = "") : Bytes
        body = para(r("{{ fac"), %(<w:proofErr w:type="spellStart"/>), r("ture.type }} {{ facture.nu", bold: true), r("mero }}")) +
               para(r("Date : {{ facture.date }} — Échéance : {{ facture.echeance }}")) +
               para(r("{{ vendeur.nom }}"), r(" · {{ vendeur."), r("adresse }}")) +
               para(r("{{ client.nom }} · {{ client.adresse }}")) +
               tbl(
                 tr(para(r("Désignation")), para(r("Qté")), para(r("PU")), para(r("TVA")), para(r("Total"))),
                 tr(para(r("{% for lig"), r("ne in lignes %}{{ ligne.designation }}")), para(r("{{ ligne.quantite }}")),
                   para(r("{{ ligne.prix_unitaire }}")), para(r("{{ ligne.taux_tva }}")), para(r("{{ ligne.montant_ht }}{% end"), r("for %}")))
               ) +
               para(r("{% if totaux.acompte %}")) + para(r("Acompte : {{ totaux.acompte }}")) + para(r("{% endif %}")) +
               para(r("HT {{ totaux.ht }} TVA {{ totaux.tva }} TTC {{ totaux.ttc }}")) +
               extra +
               para(r("{{ mentions }}"))
        docx(body)
      end

      def self.invoice_odt(extra : String = "") : Bytes
        odt(invoice_odt_body(extra))
      end

      def self.invoice_odt_body(extra : String = "") : String
        tp("{{ fac", span("ture.type }} {{ facture.nu"), "mero }}") +
          tp("Date : {{ facture.date }} — Échéance : {{ facture.echeance }}") +
          tp("{{ vendeur.nom }} · ", span("{{ vendeur.adr"), "esse }}") +
          tp("{{ client.nom }} · {{ client.adresse }}") +
          table(
            row(tp("Désignation"), tp("Qté"), tp("PU"), tp("TVA"), tp("Total")),
            row(tp(span("{% for ligne in lig"), "nes %}{{ ligne.designation }}"), tp("{{ ligne.quantite }}"),
              tp("{{ ligne.prix_unitaire }}"), tp("{{ ligne.taux_tva }}"), tp("{{ ligne.montant_ht }}", span("{% endfor %}")))
          ) +
          tp("{% if totaux.acompte %}") + tp("Acompte : {{ totaux.acompte }}") + tp("{% endif %}") +
          tp("HT {{ totaux.ht }} TVA {{ totaux.tva }} TTC {{ totaux.ttc }}") +
          extra +
          tp("{{ mentions }}")
      end
    end
  end
end
