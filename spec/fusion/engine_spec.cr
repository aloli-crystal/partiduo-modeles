# SPDX-License-Identifier: AGPL-3.0-or-later

require "../spec_helper"

private def sample(kind = "invoice", locale = "fr") : Partiduo::Api::Invoicing::DocumentView
  Modeles::Sample.document(kind, locale, Time.utc(2026, 9, 15))
end

# Rendu d'un texte ; pour ODT et DOCX, fusion d'une partie XML seule
# (sans archive).
private def render(source : String, format = "markdown", view = sample, marker : String? = nil) : String
  if Modeles::Config.office?(format)
    Modeles::Fusion::Engine.render(source, Modeles::Fusion::ContextBuilder.new(view, format, marker).build, escape: true)
  else
    String.new(Modeles::Fusion.render(format, source.to_slice, view, marker))
  end
end

describe "Moteur de fusion (ADR-010 D2)" do
  it "remplit le vocabulaire complet depuis la vue du document" do
    paths = Modeles::Fusion::Vocabulary::OBJECTS.flat_map { |group, fields| fields.map { |field| "#{group}.#{field}" } }
    source = paths.map { |path| "#{path}=[{{ #{path} }}]" }.join('\n')
    text = render(source, "docx")
    text.should contain("facture.numero=[F-EXEMPLE-0001]")
    text.should contain("facture.type=[Facture]")
    text.should contain("facture.date=[15/09/2026]")
    text.should contain("facture.echeance=[15/10/2026]")
    text.should contain("facture.conditions_paiement=[Paiement à 30 jours (échéance le 15/10/2026)]")
    text.should contain("vendeur.siren=[123456789]")
    text.should contain("client.nom=[Client Modèle &amp; Fils]")
    text.should contain("client.adresse=[3 avenue du Commerce#{Modeles::Fusion::Escaper::NEWLINE}Bâtiment B")
    text.should contain("totaux.ttc=[1 759,15]")
    text.should contain("reglement.iban=[FR76 3000 6000 0112 3456 7890 189]")
    text.should contain("reglement.bic=[AGRIFRPP]")
    text.should contain("facture.brouillon=[false]")
    text.should contain("facture.validite=[]")
  end

  it "parcourt les lignes, la ventilation de TVA et les mentions" do
    source = "{% for ligne in lignes %}{{ loop.index }}:{{ ligne.designation }}|{{ ligne.quantite }}|{{ ligne.unite }}|" \
             "{{ ligne.taux_tva }}|{{ ligne.montant_ht }}{% if ligne.titre %}(titre){% endif %};{% endfor %}\n" \
             "{% for groupe in tva %}{{ groupe.taux }}={{ groupe.montant }};{% endfor %}\n" \
             "{% for mention in mentions %}[{{ mention.code }}]{% endfor %}"
    text = render(source, "docx")
    text.should contain("1:Prestations||||(titre);")
    text.should contain("2:Conseil en organisation#{Modeles::Fusion::Escaper::NEWLINE}Atelier d&#39;une demi-journée|3|h|20 %|1 350,00;")
    text.should contain("3:Frais de déplacement|1|u.|20 %|72,00;")
    text.should contain("20 %=284,40;5,5 %=2,75;")
    text.should contain("[payment.indemnity]")
  end

  it "imprime les mentions légales dans la langue du document" do
    render("{{ mentions }}", "markdown", sample("invoice", "en")).should contain("Late payment")
    fr = render("{{ mentions }}", "markdown")
    fr.should contain("Indemnité forfaitaire pour frais de recouvrement en cas de retard de paiement : 40,00 €")
    fr.should contain("SIREN : 123456789\\\n")
    nl = render("{{ totaux.ttc }} {{ facture.date }} {{ facture.type }}", "markdown", sample("invoice", "nl"))
    nl.should eq("1.759,15 15-09-2026 Factuur")
    render("{{ totaux.ttc }} {{ facture.date }}", "markdown", sample("invoice", "en")).should eq("1,759.15 2026-09-15")
  end

  it "rend une valeur vide fausse dans une condition et remplacée par default" do
    render("{% if facture.validite %}oui{% else %}non{% endif %} {{ facture.notes|default:\"—\" }}").should eq("non —")
    render("{% if facture.validite %}oui{% else %}non{% endif %}", "markdown", sample("quote")).should eq("oui")
  end

  it "échappe les valeurs selon le format du modèle" do
    view = sample
    hostile = view.copy_with(customer: view.customer.copy_with(name: "A*B_[x]|<y>&z"))
    render("{{ client.nom }}", "markdown", hostile).should eq("A\\*B\\_\\[x\\]\\|\\<y\\>\\&z")
    render("{{ client.nom }}", "asciidoc", hostile).should eq("A&#42;B&#95;&#91;x&#93;&#124;&#60;y&#62;&#38;z")
    render("<w:t>{{ client.nom }}</w:t>", "docx", hostile).should eq("<w:t>A*B_[x]|&lt;y&gt;&amp;z</w:t>")
  end

  it "marque un rendu sans valeur en tête du document" do
    marked = render("= {{ facture.type }}\n:nofooter:\n\nCorps", "asciidoc", sample, "Brouillon — sans valeur")
    marked.should start_with("= Facture\n:nofooter:\n\n*Brouillon — sans valeur*")
    marked.should contain("Corps")
    render("Corps", "markdown", sample, "Brouillon — sans valeur").should start_with("**Brouillon — sans valeur**")
  end

  it "ne rend jamais un gabarit refusé par le contrôle" do
    expect_raises(Modeles::Fusion::TemplateRejected) { render("{% include 'ui/base.html' %}") }
    expect_raises(Modeles::Fusion::TemplateRejected) { render("{{ client.nom|safe }}") }
  end
end
