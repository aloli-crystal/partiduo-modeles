# SPDX-License-Identifier: AGPL-3.0-or-later

module Modeles
  module SpecSupport
    # Corps `multipart/form-data` d'un formulaire avec un fichier.
    def self.multipart(fields : Hash(String, String), file : {String, String, Bytes}?) : {String, String}
      io = IO::Memory.new
      boundary = "PartiduoModelesSpecBoundary"
      HTTP::FormData.build(io, boundary) do |builder|
        fields.each { |name, value| builder.field(name, value) }
        if file
          builder.file(file[0], IO::Memory.new(file[2]), HTTP::FormData::FileMetadata.new(filename: file[1]))
        end
      end
      {io.to_s, "multipart/form-data; boundary=#{boundary}"}
    end

    # Envoi d'un formulaire multipart par le navigateur de test (cookies
    # gardés).
    def self.upload(browser : PartiduoUi::Browser, path : String, fields : Hash(String, String),
                    file : {String, String, Bytes}?) : Marten::HTTP::Response
      body, content_type = multipart(fields, file)
      client = Marten::Spec::Client.new
      browser.jar.each { |name, value| client.cookies[name] = value }
      response = client.post(path, data: body, content_type: content_type, headers: browser.headers)
      client.cookies.each { |(name, value)| value.empty? ? browser.jar.delete(name) : (browser.jar[name] = value) }
      response
    end

    # Navigateur connecté d'un utilisateur au profil limité à `permissions`.
    def self.signed_in_with(permissions : Array(String), email : String = "lecteur@example.com") : PartiduoUi::Browser
      profile = PartiduoUi::Accounts.profile("Profil #{email}", permissions)
      PartiduoUi::Accounts.create(email: email, profile: nil, profile_id: profile)
      PartiduoUi::Accounts.signed_in(email)
    end
  end
end
