# SPDX-License-Identifier: AGPL-3.0-or-later

# Interface Bulma de l'extension MODELES (ADR-010, ADR-005 D4) : liste des
# modèles, dépôt avec rapport de contrôle, aperçu, activation, défaut par
# type et langue, modèles de départ, « Rendre avec un modèle » depuis la
# fiche d'un document de la Facturation (panneau de l'extension, avec ses
# rendus conservés), historique des rendus. Montée par
# `partiduo-ui-bulma` sous `/ext/MODELES/` (ADR-003 D3). La distribution la
# requiert après l'interface :
#
# ```
# require "partiduo-ui-bulma/partiduo_ui"
# require "partiduo-modeles"
# require "partiduo-modeles/ui/bulma"
# ```
#
# puis ajoute `Modeles::Ui::INSTALLED_APPS` à ses applications Marten.
# Ce dossier ne parle au métier que par `Modeles::Api` et `Partiduo::Api`
# (vérifié par `spec/architecture/conventions_spec.cr`).
require "../../src/partiduo-modeles"

require "./presenters"
require "./handlers/**"
require "./document_links"

module Modeles
  module Ui
    # Application Marten de l'interface Bulma de l'extension : gabarits
    # (`templates/modeles/`), fichiers statiques (`assets/modeles/`) et
    # libellés d'écran (`locales/`, clés `modeles_ui.*`).
    class App < Marten::App
      label "modeles_ui"
    end

    INSTALLED_APPS = [Modeles::Ui::App] of Marten::Apps::Config.class

    # Routes servies sous `/ext/MODELES/`, nommées `modeles:<nom>`.
    ROUTES = Marten::Routing::Map.draw do
      path "/", Modeles::Ui::IndexHandler, name: "index"
      path "/upload", Modeles::Ui::UploadHandler, name: "upload"
      path "/templates/<id:int>", Modeles::Ui::TemplateHandler, name: "template"
      path "/templates/<id:int>/versions/<number:int>/file", Modeles::Ui::VersionFileHandler, name: "version_file"
      path "/templates/<id:int>/versions/<number:int>/preview", Modeles::Ui::PreviewHandler, name: "preview"
      path "/templates/<id:int>/activate", Modeles::Ui::ActivateHandler, name: "activate"
      path "/templates/<id:int>/default", Modeles::Ui::DefaultHandler, name: "default"
      path "/templates/<id:int>/retire", Modeles::Ui::RetireHandler, name: "retire"
      path "/starters/<kind:str>/<locale:str>/<format:str>", Modeles::Ui::StarterHandler, name: "starter"
      path "/documents", Modeles::Ui::DocumentsHandler, name: "documents"
      path "/documents/<id:int>", Modeles::Ui::DocumentHandler, name: "document"
      path "/documents/<id:int>/render", Modeles::Ui::RenderHandler, name: "render"
      path "/renditions", Modeles::Ui::RenditionsHandler, name: "renditions"
      path "/renditions/<id:int>/<variant:str>", Modeles::Ui::RenditionFileHandler, name: "rendition_file"
    end

    # Routes qui déposent ou changent un modèle : `modeles.admin` ; les
    # autres (listes, aperçus, rendus, téléchargements) : `modeles.read`.
    ADMIN_ROUTES = %w[upload activate default retire]
  end
end

PartiduoUi::Extensions.mount Modeles::CODE, Modeles::Ui::ROUTES, permission: Modeles::Api::READ,
  permissions: Modeles::Ui::ADMIN_ROUTES.to_h { |route| {route, Modeles::Api::ADMIN} }
