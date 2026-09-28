# {{ facture.type }} {{ facture.numero }}

**{{ vendeur.nom }}**\
{{ vendeur.adresse }}{% if vendeur.courriel %}\
{{ vendeur.courriel }}{% endif %}

**Client**\
{{ client.nom }}\
{{ client.adresse }}

| | |
|:--|:--|
| Date | {{ facture.date }} |
{% if facture.facture_origine %}| Facture d'origine | {{ facture.facture_origine }} |
{% endif %}{% if facture.facture_origine_date %}| Du | {{ facture.facture_origine_date }} |
{% endif %}{% if facture.reference_acheteur %}| Votre référence | {{ facture.reference_acheteur }} |
{% endif %}{% if facture.reference_commande %}| Votre commande | {{ facture.reference_commande }} |
{% endif %}
| Désignation | Qté | Unité | PU HT | TVA | Total HT |
|:--|--:|:--|--:|--:|--:|
{% for ligne in lignes %}{% if ligne.chiffree %}| {{ ligne.designation }}{% if ligne.remise %} (remise {{ ligne.remise }}){% endif %} | {{ ligne.quantite }} | {{ ligne.unite }} | {{ ligne.prix_unitaire }} | {{ ligne.taux_tva }} | {{ ligne.montant_ht }} |
{% elsif ligne.sous_total %}| *{{ ligne.designation|default:"Sous-total" }}* | | | | | *{{ ligne.montant_ht }}* |
{% elsif ligne.note %}| *{{ ligne.designation }}* | | | | | |
{% else %}| **{{ ligne.designation }}** | | | | | |
{% endif %}{% endfor %}
| Taux de TVA | Base HT | Montant de TVA |
|--:|--:|--:|
{% for groupe in tva %}| {{ groupe.taux }} | {{ groupe.base }} | {{ groupe.montant }} |
{% endfor %}
| | |
|:--|--:|
| Total HT | {{ totaux.ht }} {{ facture.devise }} |
| Total TVA | {{ totaux.tva }} {{ facture.devise }} |
| **Total TTC** | **{{ totaux.ttc }} {{ facture.devise }}** |
{% if totaux.acompte %}| Acomptes déduits | {{ totaux.acompte }} {{ facture.devise }} |
| **Net à payer** | **{{ totaux.net_a_payer }} {{ facture.devise }}** |
{% endif %}
{% if facture.conditions_paiement %}**Conditions de paiement :** {{ facture.conditions_paiement }}

{% endif %}{% if facture.origine %}{{ facture.origine }}

{% endif %}{% if facture.notes %}{{ facture.notes }}

{% endif %}**Mentions légales**\
{{ mentions }}
