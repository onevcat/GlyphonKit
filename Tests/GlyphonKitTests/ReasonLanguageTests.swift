import Testing
@testable import GlyphonKit

@Suite("Reason Language")
struct ReasonLanguageTests {
  @Test func followsAConfidentDetection() {
    let code = ReasonLanguage.code(hypotheses: ["es": 0.90, "ca": 0.10], preferredLanguages: ["zh-Hans", "en"])
    #expect(code == "es")
  }

  @Test func doesNotTrustAWeakGuessOnShortLatinText() {
    // "gameconsole" (a pinyin keyboard ate the space) was read as Italian
    // and the reason came back in Italian.
    let code = ReasonLanguage.code(
      hypotheses: ["it": 0.39, "en": 0.16, "fr": 0.09],
      preferredLanguages: ["zh-Hans", "en", "ja"]
    )
    #expect(code == "en")
  }

  @Test func prefersALanguageTheUserReadsWhenUnsure() {
    let code = ReasonLanguage.code(
      hypotheses: ["es": 0.52, "ca": 0.27, "it": 0.12],
      preferredLanguages: ["it"]
    )
    #expect(code == "it")
  }

  @Test func fallsBackToEnglishWhenUnsureAndNothingMatches() {
    let code = ReasonLanguage.code(hypotheses: ["ro": 0.29, "id": 0.20, "pt": 0.11], preferredLanguages: ["ja"])
    #expect(code == "en")
  }

  @Test func countsScriptVariantsAsOneLanguage() {
    let hypotheses = ["zh-Hant": 0.53, "zh-Hans": 0.40]
    #expect(ReasonLanguage.code(hypotheses: hypotheses, preferredLanguages: ["zh-Hans", "en"]) == "zh-Hans")
    #expect(ReasonLanguage.code(hypotheses: hypotheses, preferredLanguages: ["en"]) == "zh-Hant")
  }

  @Test func usesEnglishWithoutAnyHypothesis() {
    #expect(ReasonLanguage.code(hypotheses: [:], preferredLanguages: ["ja"]) == "en")
  }

  @Test func reducesPreferredLanguagesToRecognizerCodes() {
    let codes = ReasonLanguage.recognizerCodes(
      preferredLanguages: ["zh-Hans-JP", "en-JP", "ja-JP", "pt-BR", "zh-Hant-TW"]
    )
    #expect(codes == ["zh-Hans", "en", "ja", "pt", "zh-Hant"])
  }

  @Test func infersTheChineseScriptFromTheRegion() {
    #expect(ReasonLanguage.recognizerCodes(preferredLanguages: ["zh-TW", "zh-HK", "zh-CN", "zh"]) == ["zh-Hant", "zh-Hant", "zh-Hans", "zh-Hans"])
  }

  @Test func namesTheLanguageInEnglishForThePrompt() {
    #expect(ReasonLanguage.name(forCode: "en") == "English")
    #expect(ReasonLanguage.name(forCode: "zh-Hans") == "Chinese, Simplified")
  }
}
