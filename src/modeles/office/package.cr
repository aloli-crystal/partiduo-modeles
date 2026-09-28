# SPDX-License-Identifier: AGPL-3.0-or-later

require "compress/zip"
require "digest/crc32"

module Modeles
  module Office
    # Archive illisible, ou qui n'est pas un document du format annoncé.
    class InvalidPackage < Exception
    end

    # Archive ZIP d'un document ODT ou DOCX, lue et réécrite avec
    # `Compress::Zip` de la bibliothèque standard. L'ordre des entrées est
    # gardé ; `mimetype` (ODT) est réécrit en premier et sans compression,
    # comme l'exige OpenDocument (ODF 1.2, partie 3, § 3.3).
    class Package
      # Limites de lecture : nombre d'entrées et taille décompressée totale
      # (protection contre les archives piégées).
      MAX_ENTRIES         = 2_000
      MAX_UNCOMPRESSED    = 200 * 1024 * 1024
      MIMETYPE            = "mimetype"
      DETERMINISTIC_EPOCH = Time.utc(2026, 1, 1)

      record Entry, name : String, data : Bytes

      getter entries : Array(Entry)

      def initialize(@entries : Array(Entry) = [] of Entry)
      end

      def self.read(bytes : Bytes) : Package
        raise InvalidPackage.new("archive vide") if bytes.empty?
        entries = [] of Entry
        total = 0_i64
        Compress::Zip::File.open(IO::Memory.new(bytes)) do |zip|
          raise InvalidPackage.new("trop d'entrées") if zip.entries.size > MAX_ENTRIES
          zip.entries.each do |entry|
            next if entry.dir?
            total += entry.uncompressed_size
            raise InvalidPackage.new("archive trop volumineuse") if total > MAX_UNCOMPRESSED
            data = entry.open do |io|
              buffer = IO::Memory.new
              IO.copy(io, buffer, entry.uncompressed_size.to_i64 + 1)
              buffer.to_slice
            end
            entries << Entry.new(entry.filename, data)
          end
        end
        new(entries)
      rescue error : InvalidPackage
        raise error
      rescue error
        raise InvalidPackage.new("archive ZIP illisible : #{error.message}")
      end

      def []?(name : String) : Bytes?
        @entries.find { |entry| entry.name == name }.try(&.data)
      end

      def text(name : String) : String?
        self[name]?.try { |data| String.new(data) }
      end

      def names : Array(String)
        @entries.map(&.name)
      end

      # Remplace (ou ajoute) une entrée, à sa place.
      def []=(name : String, content : String | Bytes) : Nil
        data = content.is_a?(String) ? content.to_slice : content
        if index = @entries.index { |entry| entry.name == name }
          @entries[index] = Entry.new(name, data)
        else
          @entries << Entry.new(name, data)
        end
      end

      # Archive réécrite : `mimetype` d'abord, sans compression ; les autres
      # entrées compressées, datées de `time` (fixe par défaut : deux
      # écritures du même contenu donnent la même archive).
      def to_bytes(time : Time = DETERMINISTIC_EPOCH) : Bytes
        io = IO::Memory.new
        Compress::Zip::Writer.open(io) do |zip|
          if mimetype = self[MIMETYPE]?
            entry = Compress::Zip::Writer::Entry.new(MIMETYPE, time: time)
            entry.compression_method = Compress::Zip::CompressionMethod::STORED
            entry.crc32 = Digest::CRC32.checksum(mimetype)
            entry.compressed_size = entry.uncompressed_size = mimetype.size.to_u32
            zip.add(entry, mimetype)
          end
          @entries.each do |item|
            next if item.name == MIMETYPE
            zip.add(Compress::Zip::Writer::Entry.new(item.name, time: time), item.data)
          end
        end
        io.to_slice
      end
    end
  end
end
