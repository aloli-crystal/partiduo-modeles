# {{ facture.type }} {{ facture.numero }}

**{{ vendeur.nom }}**\
{{ vendeur.adresse }}{% if vendeur.courriel %}\
{{ vendeur.courriel }}{% endif %}

**Customer**\
{{ client.nom }}\
{{ client.adresse }}

| | |
|:--|:--|
| Date | {{ facture.date }} |
{% if facture.date_livraison %}| Delivery date | {{ facture.date_livraison }} |
{% endif %}{% if facture.echeance %}| Due date | {{ facture.echeance }} |
{% endif %}{% if facture.reference_acheteur %}| Your reference | {{ facture.reference_acheteur }} |
{% endif %}{% if facture.reference_commande %}| Your order | {{ facture.reference_commande }} |
{% endif %}
| Description | Qty | Unit | Unit price | VAT | Amount |
|:--|--:|:--|--:|--:|--:|
{% for ligne in lignes %}{% if ligne.chiffree %}| {{ ligne.designation }}{% if ligne.remise %} (discount {{ ligne.remise }}){% endif %} | {{ ligne.quantite }} | {{ ligne.unite }} | {{ ligne.prix_unitaire }} | {{ ligne.taux_tva }} | {{ ligne.montant_ht }} |
{% elsif ligne.sous_total %}| *{{ ligne.designation|default:"Subtotal" }}* | | | | | *{{ ligne.montant_ht }}* |
{% elsif ligne.note %}| *{{ ligne.designation }}* | | | | | |
{% else %}| **{{ ligne.designation }}** | | | | | |
{% endif %}{% endfor %}
| VAT rate | Taxable amount | VAT amount |
|--:|--:|--:|
{% for groupe in tva %}| {{ groupe.taux }} | {{ groupe.base }} | {{ groupe.montant }} |
{% endfor %}
| | |
|:--|--:|
| Total excl. VAT | {{ totaux.ht }} {{ facture.devise }} |
| Total VAT | {{ totaux.tva }} {{ facture.devise }} |
| **Total incl. VAT** | **{{ totaux.ttc }} {{ facture.devise }}** |
{% if totaux.acompte %}| Deposits deducted | {{ totaux.acompte }} {{ facture.devise }} |
| **Amount due** | **{{ totaux.net_a_payer }} {{ facture.devise }}** |
{% endif %}
{% if facture.conditions_paiement %}**Payment terms:** {{ facture.conditions_paiement }}

{% endif %}{% if reglement.iban %}**Payment:** IBAN {{ reglement.iban }}{% if reglement.bic %} · BIC {{ reglement.bic }}{% endif %} · reference {{ reglement.reference }}

{% endif %}{% if facture.origine %}{{ facture.origine }}

{% endif %}{% if facture.notes %}{{ facture.notes }}

{% endif %}**Legal notices**\
{{ mentions }}
