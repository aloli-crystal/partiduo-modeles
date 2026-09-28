# SPDX-License-Identifier: AGPL-3.0-or-later

module Modeles
  # Rendu conservé d'un document émis de la Facturation (ADR-010 D4) : le
  # fichier au format du modèle et, si le convertisseur l'a produit, le PDF,
  # avec leurs empreintes et la version du modèle. `document_id` est
  # l'identifiant lu par `Partiduo::Api::Invoicing`, sans clé étrangère vers
  # une table interne du cœur. `pdf_error` : clé de traduction de l'échec de
  # la conversion (vide si le PDF a été produit ou n'était pas demandé).
  class Rendition < Marten::Model
    field :id, :big_int, primary_key: true, auto: true
    field :document_id, :big_int, index: true
    field :document_kind, :string, max_size: 32
    field :document_number, :string, max_size: 64
    field :locale, :string, max_size: 2
    field :template_id, :big_int, index: true
    field :version_id, :big_int
    field :version_number, :int
    field :format, :string, max_size: 16
    field :file_id, :big_int
    field :sha256, :string, max_size: 64
    field :pdf_file_id, :big_int, blank: true, null: true
    field :pdf_sha256, :string, max_size: 64, blank: true, null: true
    field :pdf_error, :string, max_size: 128, blank: true, default: ""
    field :rendered_by_id, :big_int, blank: true, null: true

    with_timestamp_fields
  end
end
