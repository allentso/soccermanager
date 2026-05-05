import { describe, expect, it } from "vitest";

import de from "./locales/de.json";
import en from "./locales/en.json";
import es from "./locales/es.json";
import fr from "./locales/fr.json";
import it from "./locales/it.json";
import ptBR from "./locales/pt-BR.json";
import pt from "./locales/pt.json";
import zhCN from "./locales/zh-CN.json";

type LocaleTree = Record<string, unknown>;

const LOCALES: Record<string, LocaleTree> = {
  de,
  es,
  fr,
  it,
  pt,
  "pt-BR": ptBR,
  "zh-CN": zhCN,
};

function collectMissingKeys(
  reference: LocaleTree,
  candidate: LocaleTree,
  path: string[] = [],
): string[] {
  return Object.entries(reference).flatMap(([key, value]) => {
    const nextPath = [...path, key];
    const candidateValue = candidate[key];

    if (value !== null && typeof value === "object" && !Array.isArray(value)) {
      if (
        candidateValue === null ||
        typeof candidateValue !== "object" ||
        Array.isArray(candidateValue)
      ) {
        return [nextPath.join(".")];
      }

      return collectMissingKeys(
        value as LocaleTree,
        candidateValue as LocaleTree,
        nextPath,
      );
    }

    return candidateValue === undefined ? [nextPath.join(".")] : [];
  });
}

describe("locale coverage", () => {
  it("keeps every supported locale aligned with English translation keys", () => {
    const missingKeysByLocale = Object.entries(LOCALES).reduce<
      Record<string, string[]>
    >((accumulator, [localeCode, translations]) => {
      const missingKeys = collectMissingKeys(en, translations);

      if (missingKeys.length > 0) {
        accumulator[localeCode] = missingKeys;
      }

      return accumulator;
    }, {});

    expect(missingKeysByLocale).toEqual({});
  });
});
