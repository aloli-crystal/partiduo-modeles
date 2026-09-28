# SPDX-License-Identifier: AGPL-3.0-or-later

module Modeles
  module Starters
    # Élément d'un modèle de départ de traitement de texte, décrit une fois
    # pour ODT et DOCX : paragraphe (fragments `{texte, gras}`), tableau
    # (lignes de cellules ; largeurs relatives ; `header` : première ligne en
    # gras sur fond gris ; `borders`).
    alias Run = {String, Bool}

    record Paragraph, runs : Array(Run), size : Int32? = nil, align_end : Bool = false

    record Table, widths : Array(Int32), rows : Array(Array(Array(Paragraph))), header : Bool = false,
      borders : Bool = true, align_end : Array(Int32) = [] of Int32

    alias Element = Paragraph | Table

    # Contenu commun des modèles de départ ODT et DOCX. Les blocs
    # conditionnels du corps sont des paragraphes qui ne contiennent que la
    # balise (`{% if … %}`, `{% endif %}`) : ils disparaissent à la fusion.
    # La ligne du tableau des lignes ouvre la boucle dans sa première cellule
    # et la ferme dans la dernière (ligne répétée).
    module Office
      def self.para(text : String, bold : Bool = false, size : Int32? = nil, align_end : Bool = false) : Paragraph
        Paragraph.new([{text, bold}], size, align_end)
      end

      def self.cell(text : String, bold : Bool = false) : Array(Paragraph)
        [para(text, bold)]
      end

      def self.elements(layout : Layout) : Array(Element)
        t = ->(key : String) { layout.t(key) }
        list = [] of Element
        list << para(layout.title, bold: true, size: 18)
        seller = [para("{{ vendeur.nom }}", bold: true), para("{{ vendeur.adresse }}"),
                  para("{{ vendeur.courriel }}")]
        customer = [para(t.call("customer"), bold: true), para("{{ client.nom }}"), para("{{ client.adresse }}")]
        list << Table.new([50, 50], [[seller, customer]], borders: false)
        list << para("")
        list << para("#{t.call("date")} : {{ facture.date }}")
        layout.infos.each do |info|
          list << para("{% if #{info.field} %}")
          list << para("#{info.label} : {{ #{info.field} }}")
          list << para("{% endif %}")
        end
        list << para("")
        header = [t.call("description"), t.call("quantity"), t.call("unit"), t.call("unit_price"), t.call("vat"),
                  t.call("line_total")].map { |label| cell(label, bold: true) }
        description = Paragraph.new([
          {"{% for ligne in lignes %}{% if ligne.chiffree %}#{layout.priced_description}{% endif %}", false},
          {"{% if ligne.titre %}{{ ligne.designation }}{% endif %}", true},
          {"{% if ligne.note %}{{ ligne.designation }}{% endif %}", false},
          {"{% if ligne.sous_total %}#{layout.subtotal_description}{% endif %}", true},
        ])
        row = [[description], cell("{{ ligne.quantite }}"), cell("{{ ligne.unite }}"), cell("{{ ligne.prix_unitaire }}"),
               cell("{{ ligne.taux_tva }}"), cell("{{ ligne.montant_ht }}{% endfor %}")]
        list << Table.new([40, 9, 9, 15, 10, 17], [header, row], header: true, align_end: [1, 3, 4, 5])
        list << para("")
        vat_header = [t.call("vat_rate"), t.call("vat_base"), t.call("vat_amount")].map { |label| cell(label, bold: true) }
        vat_row = [cell("{% for groupe in tva %}{{ groupe.taux }}"), cell("{{ groupe.base }}"), cell("{{ groupe.montant }}{% endfor %}")]
        list << Table.new([20, 40, 40], [vat_header, vat_row], header: true, align_end: [0, 1, 2])
        list << para("")
        totals = [
          [cell(t.call("total_net")), cell(layout.amount("totaux.ht"))],
          [cell(t.call("total_vat")), cell(layout.amount("totaux.tva"))],
          [cell(t.call("total_gross"), bold: true), cell(layout.amount("totaux.ttc"), bold: true)],
          [cell("{% if totaux.acompte %}#{t.call("prepaid")}"), cell(layout.amount("totaux.acompte"))],
          [cell(t.call("payable"), bold: true), cell("#{layout.amount("totaux.net_a_payer")}{% endif %}", bold: true)],
        ]
        list << Table.new([60, 40], totals, align_end: [1])
        list << para("")
        list << para("{% if facture.conditions_paiement %}")
        list << Paragraph.new([{t.call("terms"), true}, {" {{ facture.conditions_paiement }}", false}])
        list << para("{% endif %}")
        if layout.invoice?
          list << para("{% if reglement.iban %}")
          list << Paragraph.new([{t.call("payment"), true},
                                 {" IBAN {{ reglement.iban }}{% if reglement.bic %} · BIC {{ reglement.bic }}{% endif %} · #{t.call("reference")} {{ reglement.reference }}", false}])
          list << para("{% endif %}")
        end
        list << para("{% if facture.origine %}")
        list << para("{{ facture.origine }}")
        list << para("{% endif %}")
        list << para("{% if facture.notes %}")
        list << para("{{ facture.notes }}")
        list << para("{% endif %}")
        list << para(t.call("legal"), bold: true)
        list << para("{{ mentions }}", size: 8)
        list
      end

      def self.xml(text : String) : String
        text.gsub('&', "&amp;").gsub('<', "&lt;").gsub('>', "&gt;")
      end
    end

    # Modèle de départ DOCX (Office Open XML, ECMA-376) minimal : types de
    # contenu, relations, styles, document.
    class DocxBuilder
      def initialize(@layout : Layout)
      end

      def build : Bytes
        package = Modeles::Office::Package.new
        package["[Content_Types].xml"] = <<-XML
          <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
          <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/></Types>
          XML
        package["_rels/.rels"] = <<-XML
          <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
          <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>
          XML
        package["word/_rels/document.xml.rels"] = <<-XML
          <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
          <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>
          XML
        package["word/styles.xml"] = <<-XML
          <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
          <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Liberation Sans" w:hAnsi="Liberation Sans" w:cs="Liberation Sans"/><w:sz w:val="20"/><w:lang w:val="#{@layout.locale}"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after="60"/></w:pPr></w:pPrDefault></w:docDefaults><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style></w:styles>
          XML
        body = Starters::Office.elements(@layout).join { |element| element(element) }
        package["word/document.xml"] = %(<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n) +
                                       %(<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>) +
                                       body + %(<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134" w:header="567" w:footer="567" w:gutter="0"/></w:sectPr></w:body></w:document>)
        package.to_bytes
      end

      private def element(element : Element) : String
        element.is_a?(Paragraph) ? paragraph(element) : table(element)
      end

      private def paragraph(paragraph : Paragraph, align_end : Bool = false) : String
        properties = paragraph.align_end || align_end ? %(<w:pPr><w:jc w:val="end"/></w:pPr>) : ""
        runs = paragraph.runs.join do |(text, bold)|
          style = String.build do |io|
            io << "<w:b/>" if bold
            paragraph.size.try { |size| io << %(<w:sz w:val="#{size * 2}"/>) }
          end
          %(<w:r>#{style.empty? ? "" : "<w:rPr>#{style}</w:rPr>"}<w:t xml:space="preserve">#{Starters::Office.xml(text)}</w:t></w:r>)
        end
        "<w:p>#{properties}#{runs}</w:p>"
      end

      private def table(table : Table) : String
        total = 9638 # largeur utile d'une page A4 à marges de 2 cm, en vingtièmes de point
        widths = table.widths.map { |width| total * width // 100 }
        borders = if table.borders
                    %(<w:tblBorders>) + %w[top start bottom end insideH insideV].join { |side| %(<w:#{side} w:val="single" w:sz="4" w:space="0" w:color="999999"/>) } + %(</w:tblBorders>)
                  else
                    ""
                  end
        grid = widths.join { |width| %(<w:gridCol w:w="#{width}"/>) }
        rows = table.rows.map_with_index do |row, row_index|
          heading = table.header && row_index == 0
          cells = row.map_with_index do |paragraphs, column|
            shading = heading ? %(<w:shd w:val="clear" w:color="auto" w:fill="E8E8E8"/>) : ""
            content = paragraphs.join { |item| paragraph(item, align_end: table.align_end.includes?(column)) }
            %(<w:tc><w:tcPr><w:tcW w:w="#{widths[column]}" w:type="dxa"/>#{shading}</w:tcPr>#{content}</w:tc>)
          end
          header = heading ? "<w:trPr><w:tblHeader/></w:trPr>" : ""
          "<w:tr>#{header}#{cells.join}</w:tr>"
        end
        %(<w:tbl><w:tblPr><w:tblW w:w="#{total}" w:type="dxa"/>#{borders}<w:tblLayout w:type="fixed"/></w:tblPr><w:tblGrid>#{grid}</w:tblGrid>#{rows.join}</w:tbl>)
      end
    end

    # Modèle de départ ODT (OpenDocument 1.3) minimal : `mimetype` en tête
    # et sans compression, manifeste, styles automatiques, contenu.
    class OdtBuilder
      NAMESPACES = %(xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" ) +
                   %(xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0" ) +
                   %(xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" ) +
                   %(xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" ) +
                   %(xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0" office:version="1.3")

      def initialize(@layout : Layout)
        @tables = 0
        @column_styles = [] of String
      end

      def build : Bytes
        package = Modeles::Office::Package.new
        package["mimetype"] = Modeles::Office::Odt::MIMETYPE
        package["META-INF/manifest.xml"] = <<-XML
          <?xml version="1.0" encoding="UTF-8"?>
          <manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0" manifest:version="1.3"><manifest:file-entry manifest:full-path="/" manifest:media-type="application/vnd.oasis.opendocument.text"/><manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/><manifest:file-entry manifest:full-path="styles.xml" manifest:media-type="text/xml"/></manifest:manifest>
          XML
        package["styles.xml"] = %(<?xml version="1.0" encoding="UTF-8"?>\n) +
                                %(<office:document-styles #{NAMESPACES}><office:styles><style:default-style style:family="paragraph"><style:paragraph-properties fo:margin-bottom="0.1cm"/><style:text-properties style:font-name="Liberation Sans" fo:font-family="'Liberation Sans'" fo:font-size="10pt" fo:language="#{@layout.locale}"/></style:default-style></office:styles>) +
                                %(<office:automatic-styles><style:page-layout style:name="pm1"><style:page-layout-properties fo:page-width="21cm" fo:page-height="29.7cm" fo:margin-top="2cm" fo:margin-bottom="2cm" fo:margin-left="2cm" fo:margin-right="2cm"/></style:page-layout></office:automatic-styles>) +
                                %(<office:master-styles><style:master-page style:name="Standard" style:page-layout-name="pm1"/></office:master-styles></office:document-styles>)
        body = Starters::Office.elements(@layout).join { |element| element(element) }
        package["content.xml"] = %(<?xml version="1.0" encoding="UTF-8"?>\n) +
                                 %(<office:document-content #{NAMESPACES}><office:automatic-styles>#{automatic_styles}</office:automatic-styles>) +
                                 %(<office:body><office:text>#{body}</office:text></office:body></office:document-content>)
        package.to_bytes
      end

      private def automatic_styles : String
        String.build do |io|
          io << %(<style:style style:name="Pend" style:family="paragraph"><style:paragraph-properties fo:text-align="end"/></style:style>)
          io << %(<style:style style:name="Tbold" style:family="text"><style:text-properties fo:font-weight="bold"/></style:style>)
          {8, 18}.each do |size|
            io << %(<style:style style:name="Tsize#{size}" style:family="text"><style:text-properties fo:font-size="#{size}pt"/></style:style>)
            io << %(<style:style style:name="Tbold#{size}" style:family="text"><style:text-properties fo:font-weight="bold" fo:font-size="#{size}pt"/></style:style>)
          end
          io << %(<style:style style:name="Cbox" style:family="table-cell"><style:table-cell-properties fo:padding="0.08cm" fo:border="0.5pt solid #999999"/></style:style>)
          io << %(<style:style style:name="Chead" style:family="table-cell"><style:table-cell-properties fo:padding="0.08cm" fo:border="0.5pt solid #999999" fo:background-color="#e8e8e8"/></style:style>)
          io << %(<style:style style:name="Cplain" style:family="table-cell"><style:table-cell-properties fo:padding="0.08cm" fo:border="none"/></style:style>)
          @column_styles.each { |style| io << style }
        end
      end

      private def element(element : Element) : String
        element.is_a?(Paragraph) ? paragraph(element) : table(element)
      end

      private def paragraph(paragraph : Paragraph, align_end : Bool = false) : String
        style = paragraph.align_end || align_end ? %( text:style-name="Pend") : ""
        spans = paragraph.runs.join do |(text, bold)|
          name = case {bold, paragraph.size}
                 when {true, nil}  then "Tbold"
                 when {false, nil} then nil
                 else                   "#{bold ? "Tbold" : "Tsize"}#{paragraph.size}"
                 end
          content = Starters::Office.xml(text)
          name ? %(<text:span text:style-name="#{name}">#{content}</text:span>) : content
        end
        "<text:p#{style}>#{spans}</text:p>"
      end

      private def table(table : Table) : String
        @tables += 1
        name = "Tableau#{@tables}"
        columns = table.widths.map_with_index do |width, index|
          @column_styles << %(<style:style style:name="#{name}.C#{index}" style:family="table-column">) +
                            %(<style:table-column-properties style:column-width="#{(17.0 * width / 100).round(2)}cm"/></style:style>)
          %(<table:table-column table:style-name="#{name}.C#{index}"/>)
        end
        rows = table.rows.map_with_index do |row, row_index|
          heading = table.header && row_index == 0
          cells = row.map_with_index do |paragraphs, column|
            cell_style = heading ? "Chead" : (table.borders ? "Cbox" : "Cplain")
            content = paragraphs.join { |item| paragraph(item, align_end: table.align_end.includes?(column)) }
            %(<table:table-cell table:style-name="#{cell_style}" office:value-type="string">#{content}</table:table-cell>)
          end
          "<table:table-row>#{cells.join}</table:table-row>"
        end
        header, body = table.header ? {rows[0, 1], rows[1..]} : {[] of String, rows}
        header_xml = header.empty? ? "" : "<table:table-header-rows>#{header.join}</table:table-header-rows>"
        %(<table:table table:name="#{name}">#{columns.join}#{header_xml}#{body.join}</table:table>)
      end
    end
  end
end
