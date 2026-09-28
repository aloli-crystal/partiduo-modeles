# SPDX-License-Identifier: AGPL-3.0-or-later

# Manifeste de l'extension MODELES (ADR-010, ADR-003 D2) : modèles de
# factures, devis et avoirs multiformats.
#
# * Dépendance : `INVOICING` (documents lus par `Partiduo::Api::Invoicing`,
#   ADR-010 D1).
# * Permissions (ADR-010 D7) : `modeles.read` (rendre un document avec un
#   modèle, télécharger les rendus, les modèles et les modèles de départ),
#   `modeles.admin` (déposer, activer, désigner par défaut, retirer).
# * Menu « Modèles de documents » sous « Facturation ».
# * Aucun abonnement : un rendu est demandé par l'utilisateur, jamais
#   déclenché par l'émission (le PDF légal Factur-X reste la référence,
#   ADR-010 D4).
Partiduo::Modules.register do
  code "MODELES"
  name "modeles.module.name"
  version "0.1.0"
  requires_core "~> 0.1"
  depends_on "INVOICING"

  permission "modeles.read"
  permission "modeles.admin"

  menu "MODELES", parent: "BILLING", order: 70, route: "modeles:index", permission: "modeles.read",
    label: "modeles.menu.templates"

  ui "bulma", path: "ui/bulma"
end
