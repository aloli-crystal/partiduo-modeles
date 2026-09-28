# {{ facture.type }} {{ facture.numero }}

**{{ vendeur.nom }}**\
{{ vendeur.adresse }}{% if vendeur.courriel %}\
{{ vendeur.courriel }}{% endif %}

**Klant**\
{{ client.nom }}\
{{ client.adresse }}

| | |
|:--|:--|
| Datum | {{ facture.date }} |
{% if facture.validite %}| Geldig tot | {{ facture.validite }} |
{% endif %}{% if facture.reference_acheteur %}| Uw referentie | {{ facture.reference_acheteur }} |
{% endif %}{% if facture.reference_commande %}| Uw bestelling | {{ facture.reference_commande }} |
{% endif %}
| Omschrijving | Aantal | Eenheid | Eenheidsprijs | Btw | Bedrag excl. btw |
|:--|--:|:--|--:|--:|--:|
{% for ligne in lignes %}{% if ligne.chiffree %}| {{ ligne.designation }}{% if ligne.remise %} (korting {{ ligne.remise }}){% endif %} | {{ ligne.quantite }} | {{ ligne.unite }} | {{ ligne.prix_unitaire }} | {{ ligne.taux_tva }} | {{ ligne.montant_ht }} |
{% elsif ligne.sous_total %}| *{{ ligne.designation|default:"Subtotaal" }}* | | | | | *{{ ligne.montant_ht }}* |
{% elsif ligne.note %}| *{{ ligne.designation }}* | | | | | |
{% else %}| **{{ ligne.designation }}** | | | | | |
{% endif %}{% endfor %}
| Btw-tarief | Maatstaf van heffing | Btw-bedrag |
|--:|--:|--:|
{% for groupe in tva %}| {{ groupe.taux }} | {{ groupe.base }} | {{ groupe.montant }} |
{% endfor %}
| | |
|:--|--:|
| Totaal excl. btw | {{ totaux.ht }} {{ facture.devise }} |
| Totaal btw | {{ totaux.tva }} {{ facture.devise }} |
| **Totaal incl. btw** | **{{ totaux.ttc }} {{ facture.devise }}** |
{% if totaux.acompte %}| Afgetrokken voorschotten | {{ totaux.acompte }} {{ facture.devise }} |
| **Te betalen** | **{{ totaux.net_a_payer }} {{ facture.devise }}** |
{% endif %}
{% if facture.conditions_paiement %}**Betalingsvoorwaarden:** {{ facture.conditions_paiement }}

{% endif %}{% if facture.origine %}{{ facture.origine }}

{% endif %}{% if facture.notes %}{{ facture.notes }}

{% endif %}**Wettelijke vermeldingen**\
{{ mentions }}
