# SPDX-License-Identifier: AGPL-3.0-or-later

require "../spec_helper"

private alias Formatter = Modeles::Fusion::Formatter

describe Modeles::Fusion::Formatter do
  it "présente les montants selon la langue du document (ADR-010 D2)" do
    value = BigDecimal.new("-1234567.895")
    Formatter.new("fr").amount(value).should eq("-1 234 567,90")
    Formatter.new("en").amount(value).should eq("-1,234,567.90")
    Formatter.new("nl").amount(value).should eq("-1.234.567,90")
    Formatter.new("fr").amount(BigDecimal.new("0.5")).should eq("0,50")
    Formatter.new("en").amount(BigDecimal.new("12")).should eq("12.00")
  end

  it "présente les quantités sans zéros inutiles et les taux" do
    Formatter.new("fr").quantity(BigDecimal.new("2.50")).should eq("2,5")
    Formatter.new("en").quantity(BigDecimal.new("10.000")).should eq("10")
    Formatter.new("fr").percent(BigDecimal.new("5.5")).should eq("5,5 %")
    Formatter.new("en").percent(BigDecimal.new("20")).should eq("20%")
    Formatter.new("nl").percent(BigDecimal.new("21")).should eq("21%")
  end

  it "présente les dates comme le PDF légal de la Facturation" do
    day = Time.utc(2026, 9, 5)
    Formatter.new("fr").date(day).should eq("05/09/2026")
    Formatter.new("en").date(day).should eq("2026-09-05")
    Formatter.new("nl").date(day).should eq("05-09-2026")
    Formatter.new("fr").date(nil).should eq("")
  end
end
