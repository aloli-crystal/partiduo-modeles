# SPDX-License-Identifier: AGPL-3.0-or-later

require "digest/sha256"
require "uuid"

module Modeles
  # Le fichier stocké ne correspond plus à son empreinte.
  class FileCorrupted < Exception
    getter file_id : Int64

    def initialize(@file_id : Int64)
      super("fichier #{@file_id} altéré")
    end
  end

  # Conservation des fichiers de l'extension (interne ; ADR-010 D1, D4).
  #
  # * PDF, AsciiDoc et Markdown : pièces jointes du socle
  #   (`Partiduo::Api::Core.store_attachment`), le texte sous le type admis
  #   `text/plain` ;
  # * ODT et DOCX, que le socle n'admet pas encore : stockage des fichiers
  #   de l'instance sous `modeles/AAAA/MM/<uuid>.<ext>`, avec la même
  #   empreinte SHA-256 vérifiée à la lecture et le même effacement si la
  #   transaction est annulée (BLOCAGE B-MOD-001).
  #
  # Les fichiers appartiennent à l'extension : ils sont écrits et lus par
  # l'acteur système, après le contrôle des permissions de l'extension par
  # `Modeles::Api` (D-MOD-004).
  module Files
    # Type admis par le socle pour un type réel ; `nil` : stockage propre.
    CORE_TYPES = {
      "application/pdf" => "application/pdf",
      "text/asciidoc"   => "text/plain",
      "text/markdown"   => "text/plain",
    }

    def self.sha256(bytes : Bytes) : String
      Digest::SHA256.hexdigest(bytes)
    end

    # Enregistre un fichier (dans la transaction de l'appelant).
    def self.store(filename : String, content_type : String, bytes : Bytes) : StoredFile
      digest = sha256(bytes)
      if core_type = CORE_TYPES[content_type]?
        result = Partiduo::Api::Core.store_attachment(Partiduo::Api::Actor.system,
          Partiduo::Api::Core::AttachmentInput.new(filename, core_type, IO::Memory.new(bytes)))
        view = result.value? || raise "pièce jointe refusée : #{result.errors.map(&.key).join(", ")}"
        StoredFile.create!(attachment_id: view.id, filename: view.filename, content_type: content_type,
          byte_size: bytes.size.to_i64, sha256: digest)
      else
        storage = Marten.media_files_storage
        extension = File.extname(filename).downcase.gsub(/[^.a-z0-9]/, "")
        name = storage.save("modeles/#{Time.utc.to_s("%Y/%m")}/#{UUID.random}#{extension}", IO::Memory.new(bytes))
        Marten::DB::Connection.default.observe_transaction_rollback(-> { storage.delete(name) rescue nil; nil })
        StoredFile.create!(storage_name: name, filename: clean(filename),
          content_type: content_type, byte_size: bytes.size.to_i64, sha256: digest)
      end
    end

    # Contenu d'un fichier ; lève `FileCorrupted` si l'empreinte ne
    # correspond plus.
    def self.read(file : StoredFile) : Bytes
      bytes = if attachment_id = file.attachment_id
                Partiduo::Api::Core.attachment_content(Partiduo::Api::Actor.system, attachment_id.to_i64)
              else
                io = Marten.media_files_storage.open(file.storage_name.to_s)
                begin
                  io.getb_to_end
                ensure
                  io.close
                end
              end
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
