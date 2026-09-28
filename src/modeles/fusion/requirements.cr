# SPDX-License-Identifier: AGPL-3.0-or-later

module Modeles
  module Fusion
    # Mentions obligatoires d'un modèle (ADR-010 D2, D3) : ce qu'un modèle
    # doit imprimer pour que le document rendu reste une présentation fidèle
    # de la facture. Chaque exigence est satisfaite par l'un des champs
    # cités (imprimé, `{{ … }}`) ; `for:lignes` : une boucle sur les lignes.
    #
    # Le bloc `{{ mentions }}` (ou une boucle qui imprime `mention.texte`)
    # couvre à lui seul les mentions légales calculées par le cœur :
    # identifiants (SIREN, TVA) du vendeur et de l'acheteur, dates
    # d'émission, de livraison et d'échéance, pénalités de retard,
    # indemnité forfaitaire de recouvrement, escompte, exonération ou
    # autoliquidation de la TVA, facture d'origine d'un avoir, validité d'un
    # devis.
    module Requirements
      record Requirement, code : String, alternatives : Array(String)

      COMMON = [
        Requirement.new("number", %w[facture.numero]),
        Requirement.new("date", %w[facture.date]),
        Requirement.new("seller_name", %w[vendeur.nom]),
        Requirement.new("seller_address", %w[vendeur.adresse vendeur.adresse_ligne1]),
        Requirement.new("customer_name", %w[client.nom]),
        Requirement.new("customer_address", %w[client.adresse client.adresse_ligne1]),
        Requirement.new("lines", %w[for:lignes]),
        Requirement.new("line_description", %w[lignes.designation]),
        Requirement.new("line_quantity", %w[lignes.quantite]),
        Requirement.new("line_unit_price", %w[lignes.prix_unitaire]),
        Requirement.new("line_amount", %w[lignes.montant_ht]),
        Requirement.new("vat_rate", %w[lignes.taux_tva tva.taux]),
        Requirement.new("vat_amount", %w[totaux.tva tva.montant]),
        Requirement.new("total_net", %w[totaux.ht]),
        Requirement.new("total_gross", %w[totaux.ttc]),
        Requirement.new("mentions", %w[mentions mentions.texte]),
      ]

      # Exigences propres à un type de document (la date d'échéance d'une
      # facture est aussi imprimée par les mentions).
      BY_KIND = {
        "invoice"     => [Requirement.new("due_date", %w[facture.echeance mentions mentions.texte reglement.echeance])],
        "quote"       => [] of Requirement,
        "credit_note" => [Requirement.new("credited", %w[facture.facture_origine mentions mentions.texte])],
      }

      def self.for(kind : String) : Array(Requirement)
        COMMON + (BY_KIND[kind]? || [] of Requirement)
      end

      # Ajoute au rapport une erreur par exigence non satisfaite.
      def self.check(kind : String, report : Report) : Nil
        self.for(kind).each do |requirement|
          next if requirement.alternatives.any? { |path| satisfied?(path, report) }
          report.error("missing", {"requirement" => requirement.code, "fields" => requirement.alternatives.join(", ")})
        end
      end

      private def self.satisfied?(path : String, report : Report) : Bool
        if list = path.lchop?("for:")
          report.loops.includes?(list)
        else
          report.printed.includes?(path)
        end
      end
    end
  end
end
