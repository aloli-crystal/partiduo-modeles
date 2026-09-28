# SPDX-License-Identifier: AGPL-3.0-or-later

module Modeles
  module Fusion
    # Vocabulaire du contexte de fusion (ADR-010 D2) : stable, en français,
    # indépendant des noms internes de la Facturation. Décrit dans le
    # README et à l'écran (libellés `modeles.vocabulary.<groupe>.<champ>`) ;
    # tout autre nom est refusé au dépôt (« champ inconnu »).
    module Vocabulary
      PARTY = %w[nom code forme_juridique capital rcs siren siret tva adresse adresse_ligne1 adresse_ligne2
        code_postal ville pays courriel telephone]

      # Objets : `{{ facture.numero }}`.
      OBJECTS = {
        "facture" => %w[numero type nature code_type date date_livraison echeance validite devise
          reference_acheteur reference_commande reference_paiement conditions_paiement categorie_operation
          remise_globale notes origine facture_origine facture_origine_date langue brouillon empreinte],
        "vendeur"   => PARTY,
        "client"    => PARTY + %w[adresse_livraison professionnel],
        "totaux"    => %w[lignes_ht remise ht tva ttc acompte net_a_payer],
        "reglement" => %w[iban bic reference titulaire echeance],
      }

      # Listes : `{% for ligne in lignes %}{{ ligne.designation }}{% endfor %}`.
      LISTS = {
        "lignes" => %w[numero nature designation quantite unite prix_unitaire remise taux_tva montant_ht chiffree
          titre note sous_total],
        "tva"      => %w[taux base montant categorie motif],
        "mentions" => %w[code texte],
      }

      # Listes imprimables telles quelles (`{{ mentions }}`).
      PRINTABLE_LISTS = %w[mentions]

      # Attributs de `loop` dans une boucle (moteur de Marten).
      LOOP = %w[index index0 first? last? length revindex revindex0 odd? even? parent]

      # Tous les champs, sous la forme `groupe.champ` (documentation).
      def self.paths : Array(String)
        OBJECTS.flat_map { |group, fields| fields.map { |field| "#{group}.#{field}" } } +
          LISTS.flat_map { |group, fields| fields.map { |field| "#{group}.#{field}" } }
      end

      def self.group?(name : String) : Bool
        OBJECTS.has_key?(name) || LISTS.has_key?(name)
      end
    end
  end
end
