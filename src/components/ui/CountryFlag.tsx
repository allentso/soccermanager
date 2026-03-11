import {
  countryMarker,
  countryName,
  isValidCountryCode,
  normaliseNationality,
} from "../../lib/countries";

interface CountryFlagProps {
  code: string;
  locale?: string;
  className?: string;
  title?: string;
}

export function CountryFlag({
  code,
  locale = "en",
  className = "",
  title,
}: CountryFlagProps) {
  const normalisedCode = normaliseNationality(code).toUpperCase();

  if (!isValidCountryCode(normalisedCode)) {
    return null;
  }

  const accessibleLabel =
    title ?? countryName(normalisedCode, locale) ?? normalisedCode;
  const classes = [
    "inline-flex",
    "items-center",
    "justify-center",
    "shrink-0",
    className,
  ]
    .filter(Boolean)
    .join(" ");

  return (
    <span
      role="img"
      aria-label={accessibleLabel}
      title={accessibleLabel}
      className={classes}
    >
      {countryMarker(normalisedCode)}
    </span>
  );
}
