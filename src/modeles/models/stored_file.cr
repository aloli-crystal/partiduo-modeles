# SPDX-License-Identifier: AGPL-3.0-or-later

module Modeles
  # Fichier de l'extension (modèle déposé, rendu, PDF). Il est conservé par
  # le socle des pièces jointes (`attachment_id`) quand le socle admet son
  # type — PDF, texte (AsciiDoc et Markdown, stockés en `text/plain`) — et,
  # sinon, dans le stockage des fichiers de l'instance sous `modeles/`
  # (`storage_name`) : ODT et DOCX, que le socle n'admet pas encore
  # (BLOCAGE B-MOD-001). `content_type` est le type réel du fichier ;
  # `sha256` son empreinte, vérifiée à chaque lecture.
  class StoredFile < Marten::Model
    field :id, :big_int, primary_key: true, auto: true
    field :attachment_id, :big_int, blank: true, null: true
    field :storage_name, :string, max_size: 255, blank: true, null: true
    field :filename, :string, max_size: 255
    field :content_type, :string, max_size: 128
    field :byte_size, :big_int
    field :sha256, :string, max_size: 64

    with_timestamp_fields
  end
end
