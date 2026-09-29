# SPDX-License-Identifier: AGPL-3.0-or-later

require "digest/sha256"

module Modeles
  # Le fichier stocké ne correspond plus à son empreinte.
  class FileCorrupted < Exception
    getter file_id : Int64

    def initialize(@file_id : Int64)
      super("fichier #{@file_id} altéré")
    end
  end

  # Le socle des pièces jointes a refusé un fichier (type, signature,
  # taille) : erreurs du contrat, clés i18n du cœur.
  class StorageRefused < Exception
    getter errors : Array(Partiduo::Api::FieldError)

    def initialize(@errors : Array(Partiduo::Api::FieldError))
      super("pièce jointe refusée : #{@errors.map(&.key).join(", ")}")
    end
  end

  # Conservation des fichiers de l'extension (interne ; ADR-010 D1, D4) :
  # tous sont des pièces jointes du socle (`Partiduo::Api::Core.store_attachment`),
  # qui contrôle type, signature (ODT, DOCX, PDF) et taille ; AsciiDoc et
  # Markdown sous le type admis `text/plain`, leur type réel étant gardé
  # dans `modeles_stored_file`.
  #
  # Les fichiers appartiennent à l'extension : ils sont écrits et lus par
  # l'acteur système, après le contrôle des permissions de l'extension par
  # `Modeles::Api` (D-MOD-004).
  module Files
    # Type de la pièce jointe du socle pour chaque type réel.
    CORE_TYPES = {
      "application/pdf"             => "application/pdf",
      "text/asciidoc"               => "text/plain",
      "text/markdown"               => "text/plain",
      Config::CONTENT_TYPES["odt"]  => Config::CONTENT_TYPES["odt"],
      Config::CONTENT_TYPES["docx"] => Config::CONTENT_TYPES["docx"],
    }

    def self.sha256(bytes : Bytes) : String
      Digest::SHA256.hexdigest(bytes)
    end

    # Enregistre un fichier (dans la transaction de l'appelant) ; lève
    # `StorageRefused` si le socle le refuse.
    def self.store(filename : String, content_type : String, bytes : Bytes) : StoredFile
      core_type = CORE_TYPES[content_type]? || raise ArgumentError.new("type de fichier inconnu : #{content_type}")
      result = Partiduo::Api::Core.store_attachment(Partiduo::Api::Actor.system,
        Partiduo::Api::Core::AttachmentInput.new(filename, core_type, IO::Memory.new(bytes)))
      view = result.value? || raise StorageRefused.new(result.errors)
      StoredFile.create!(attachment_id: view.id, filename: view.filename, content_type: content_type,
        byte_size: bytes.size.to_i64, sha256: sha256(bytes))
    end

    # Contenu d'un fichier ; lève `FileCorrupted` si l'empreinte ne
    # correspond plus.
    def self.read(file : StoredFile) : Bytes
      bytes = Partiduo::Api::Core.attachment_content(Partiduo::Api::Actor.system, file.attachment_id!.to_i64)
      raise FileCorrupted.new(file.id!.to_i64) unless sha256(bytes) == file.sha256
      bytes
    rescue Partiduo::Api::AttachmentCorrupted
      raise FileCorrupted.new(file.id!.to_i64)
    end

    # Nom de fichier affichable : sans chemin ni caractère de contrôle.
    def self.clean(filename : String) : String
      name = (filename.gsub('\\', '/').split('/').last? || "").gsub(/[[:cntrl:]]/, "").strip
      name.size > 200 ? name[-200..] : name
    end

    def self.find!(id : Int64) : StoredFile
      StoredFile.filter(id: id).first || raise Partiduo::Api::NotFound.new("modeles_file", id)
    end
  end
end
