# SPDX-License-Identifier: AGPL-3.0-or-later

require "../spec_helper"

private alias Files = Modeles::SpecSupport::OfficeFiles

private def docx(xml : String) : {String, Array(Modeles::Fusion::Issue)}
  Modeles::Office::Normalizer.normalize(xml, Modeles::Office::Docx.new)
end

private def odt(xml : String) : {String, Array(Modeles::Fusion::Issue)}
  Modeles::Office::Normalizer.normalize(xml, Modeles::Office::Odt.new)
end

describe Modeles::Office::Normalizer do
  it "réunit un champ DOCX coupé en plusieurs <w:r> dans le premier fragment" do
    xml = "<w:body>" + Files.para(Files.r("N° {{ fac"), %(<w:proofErr w:type="spellStart"/>), Files.r("ture.nu", bold: true),
      %(<w:bookmarkStart w:id="0" w:name="x"/>), Files.r("mero }} fin")) + "</w:body>"
    normalized, problems = docx(xml)
    problems.should be_empty
    normalized.should contain(%(<w:t xml:space="preserve">N° {{ facture.numero }}</w:t>))
    normalized.should contain(%(<w:t xml:space="preserve"> fin</w:t>))
    normalized.should contain(%(<w:proofErr w:type="spellStart"/>))
  end

  it "réunit un champ ODT coupé en plusieurs <text:span>, espaces compris" do
    xml = %(<office:text>) + Files.tp("Total : {{", %(<text:s/>), Files.span("totaux.t"), "tc }} €") + %(</office:text>)
    normalized, _ = odt(xml)
    normalized.should contain("Total : {{ totaux.ttc }}")
    normalized.should contain("</text:span> €")
    normalized.should_not contain("<text:s/>")
  end

  it "décode les entités et redresse les guillemets typographiques d'une balise" do
    normalized, _ = docx("<w:body>" + Files.para(Files.r("{{ client.nom|default:“—” }} &amp; {% if a &gt; b %}")) + "</w:body>")
    normalized.should contain(%({{ client.nom|default:"—" }} &amp; {% if a > b %}))
  end

  it "répète la ligne de tableau qui ouvre une boucle dans une cellule et la ferme dans une autre" do
    row = Files.tr(Files.para(Files.r("{% for ligne in lignes %}{{ ligne.designation }}")), Files.para(Files.r("{{ ligne.montant_ht }}{% endfor %}")))
    normalized, _ = docx("<w:body>" + Files.tbl(Files.tr(Files.para(Files.r("Titre"))), row) + "</w:body>")
    normalized.should match(/\{% for ligne in lignes %\}<w:tr>.*\{\{ ligne\.montant_ht \}\}<\/w:t><\/w:r><\/w:p><\/w:tc><\/w:tr>\{% endfor %\}<\/w:tbl>/)
  end

  it "répète plusieurs lignes quand la boucle se ferme dans une ligne suivante (ODT)" do
    first = Files.row(Files.tp("{% for ligne in lignes %}{{ ligne.designation }}"))
    second = Files.row(Files.tp("{{ ligne.montant_ht }}{% endfor %}"))
    normalized, _ = odt("<office:text>" + Files.table(first, second) + "</office:text>")
    normalized.should match(/\{% for ligne in lignes %\}<table:table-row>.*<\/table:table-row><table:table-row>.*<\/table:table-row>\{% endfor %\}/)
  end

  it "rend conditionnelles les lignes d'un {% if %} ouvert et fermé dans des cellules différentes" do
    row = Files.tr(Files.para(Files.r("{% if totaux.acompte %}Acompte")), Files.para(Files.r("{{ totaux.acompte }}{% endif %}")))
    normalized, _ = docx("<w:body>" + Files.tbl(row) + "</w:body>")
    normalized.should contain("<w:tblGrid/>{% if totaux.acompte %}<w:tr>")
    normalized.should contain("</w:tr>{% endif %}</w:tbl>")
  end

  it "laisse dans la cellule un bloc ouvert et fermé dans le même paragraphe" do
    cell = Files.para(Files.r("{% for m in mentions %}{{ m.texte }}{% endfor %}"))
    normalized, _ = docx("<w:body>" + Files.tbl(Files.tr(cell)) + "</w:body>")
    normalized.should contain("<w:tr><w:tc>")
    normalized.should contain(%(<w:t xml:space="preserve">{% for m in mentions %}{{ m.texte }}{% endfor %}</w:t>))
  end

  it "remplace un paragraphe du corps qui ne contient que des balises de bloc" do
    xml = "<w:body>" + Files.para(Files.r("{% if facture.notes %}")) + Files.para(Files.r("{{ facture.notes }}")) +
          Files.para(Files.r(" {% endif %} ")) + "<w:sectPr/></w:body>"
    normalized, _ = docx(xml)
    normalized.should start_with("<w:body>{% if facture.notes %}<w:p>")
    normalized.should contain("</w:p>{% endif %}<w:sectPr/>")
  end

  it "signale une boucle de ligne de tableau qui ne se ferme pas dans une ligne" do
    row = Files.tr(Files.para(Files.r("{% for ligne in lignes %}{{ ligne.designation }}")), Files.para(Files.r("x")))
    xml = "<w:body>" + Files.tbl(row) + Files.para(Files.r("{% endfor %} fin")) + "</w:body>"
    _, problems = docx(xml)
    problems.map(&.code).should eq(["row_block_unclosed"])
  end
end
