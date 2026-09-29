# SPDX-License-Identifier: AGPL-3.0-or-later

# Panneau de l'extension sur la fiche d'un document de la Facturation
# (point d'accroche `PartiduoUi::Extensions.document_links`, appelé
# seulement quand l'extension est active) : bouton « Rendre avec un modèle »
# vers l'écran de l'extension pour un devis, une facture, une facture
# d'acompte ou un avoir, et rendus conservés du document (fichier au format
# du modèle, PDF), les plus récents d'abord. Sans `modeles.read`, le contrat
# refuse (`Forbidden`) et l'interface n'affiche pas le panneau.
PartiduoUi::Extensions.document_links Modeles::CODE do |actor, document|
  links = [] of PartiduoUi::Extensions::DocumentLink
  renditions = Modeles::Api.renditions(actor, document.id, limit: Modeles::Ui::PANEL_RENDITIONS)
  if Modeles::Ui::RENDERABLE.includes?(document.kind)
    links << PartiduoUi::Extensions::DocumentLink.new(I18n.t("modeles_ui.documents.render"),
      Modeles::Ui.url("document", id: document.id))
  end
  renditions.each do |view|
    links << PartiduoUi::Extensions::DocumentLink.new(view.filename,
      Modeles::Ui.url("rendition_file", id: view.id, variant: "file"), "file")
    if view.pdf? && (pdf = view.pdf_filename)
      links << PartiduoUi::Extensions::DocumentLink.new(pdf, Modeles::Ui.url("rendition_file", id: view.id, variant: "pdf"), "file")
    end
  end
  links
end
