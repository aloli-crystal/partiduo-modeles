# SPDX-License-Identifier: AGPL-3.0-or-later

require "../spec_helper"

private def codes(source : String, kind : String? = nil) : Array(String)
  Modeles::Fusion::Analyzer.analyze(source, kind).errors.map(&.code)
end

private def issues(source : String, kind : String? = nil) : Array(Modeles::Fusion::Issue)
  Modeles::Fusion::Analyzer.analyze(source, kind).errors
end

describe Modeles::Fusion::Analyzer do
  it "admet les champs du vocabulaire, les boucles, les conditions et les filtres admis" do
    source = <<-TPL
      {{ facture.numero|upcase }} {{ client.nom|default:"—" }} {{ lignes|size }}
      {% for ligne in lignes %}{{ loop.index }}. {{ ligne.designation|truncate:40 }}{% if ligne.remise && !ligne.titre %} ({{ ligne.remise }}){% endif %}{% endfor %}
      {% unless facture.brouillon %}ok{% else %}brouillon{% endunless %}
      {% if facture.nature == "quote" %}devis{% elsif totaux.acompte %}acompte{% endif %}
      {{ lignes.0.designation }} {% for m in mentions %}{{ m.texte }}{% endfor %} {{ mentions }}
      {% verbatim %}{{ texte littéral }}{% endverbatim %}
      TPL
    issues(source).should eq([] of Modeles::Fusion::Issue)
  end

  it "refuse toute balise hors de la liste admise (moteur bridé, D2)" do
    %w[include extend url translate assign asset csrf_token block with capture cache].each do |tag|
      codes("{% #{tag} 'x' %}").should contain("tag_forbidden")
    end
  end

  it "refuse les filtres qui défont l'échappement ou sortent du vocabulaire" do
    codes("{{ client.nom|safe }}").should eq(["filter_forbidden"])
    codes("{{ client.nom|escape }}").should eq(["filter_forbidden"])
    codes("{{ client.nom|linebreaks }}").should eq(["filter_forbidden"])
  end

  it "signale les champs inconnus, y compris dans les conditions et les arguments" do
    issues("{{ facture.numro }}").should eq([Modeles::Fusion::Issue.new("unknown_field", {"field" => "facture.numro"})])
    codes("{% if request.user %}x{% endif %}").should eq(["unknown_field"])
    codes("{{ client.nom|default:settings.secret }}").should eq(["unknown_field"])
    codes("{{ vendeur.nom.id }}").should eq(["unknown_field"])
    codes("{{ loop.index }}").should eq(["unknown_field"])
    codes("{% for ligne in lignes %}{{ ligne.inconnu }}{% endfor %}").should eq(["unknown_field"])
  end

  it "signale un objet imprimé sans champ et une boucle hors liste" do
    codes("{{ vendeur }}").should eq(["incomplete_field"])
    codes("{{ lignes }}").should eq(["incomplete_field"])
    codes("{% for x in facture %}{% endfor %}").should contain("not_a_list")
  end

  it "signale une balise non fermée et une erreur de structure" do
    codes("Numéro {{ facture.numero").should eq(["unclosed"])
    codes("{% if facture.numero %}sans fin").should eq(["syntax"])
    codes("{% for ligne %}{% endfor %}").should contain("for_syntax")
  end

  it "exige les mentions obligatoires d'une facture et liste ce qui manque (D3)" do
    report = Modeles::Fusion::Analyzer.analyze("{{ facture.numero }} {{ vendeur.nom }}", "invoice")
    missing = report.errors.select(&.code.==("missing")).map { |issue| issue.params["requirement"] }
    missing.should contain("date")
    missing.should contain("customer_name")
    missing.should contain("lines")
    missing.should contain("vat_rate")
    missing.should contain("mentions")
    missing.should contain("due_date")
    missing.should_not contain("number")
  end

  it "accepte le bloc {{ mentions }} ou une boucle qui imprime mention.texte" do
    base = "{{ facture.numero }} {{ facture.date }} {{ vendeur.nom }} {{ vendeur.adresse }} {{ client.nom }} " \
           "{{ client.adresse_ligne1 }} {% for l in lignes %}{{ l.designation }} {{ l.quantite }} {{ l.prix_unitaire }} " \
           "{{ l.taux_tva }} {{ l.montant_ht }}{% endfor %} {{ totaux.ht }} {{ totaux.tva }} {{ totaux.ttc }} "
    codes(base + "{{ mentions }}", "invoice").should eq([] of String)
    codes(base + "{% for m in mentions %}{{ m.texte }}{% endfor %}", "quote").should eq([] of String)
    codes(base + "{% for m in mentions %}{{ m.code }}{% endfor %}", "credit_note").should eq(["missing", "missing"])
  end

  it "ne compte pas un champ lu seulement dans une condition comme imprimé" do
    report = Modeles::Fusion::Analyzer.analyze("{% if facture.numero %}x{% endif %}", "quote")
    report.errors.map { |issue| issue.params["requirement"]? }.should contain("number")
    report.referenced.should contain("facture.numero")
  end
end
