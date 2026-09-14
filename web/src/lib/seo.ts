import type { Metadata } from "next";

export const CANONICAL_HOST = "https://forge.mograph.life";
export const CANONICAL_BASE_PATH = "/apps/reframer";
export const SITE_NAME = "Reframer";

export function toCanonicalUrl(path = ""): string {
  const normalizedPath = path.startsWith("/") ? path : `/${path}`;
  if (normalizedPath === "/") {
    return `${CANONICAL_HOST}${CANONICAL_BASE_PATH}/`;
  }
  return `${CANONICAL_HOST}${CANONICAL_BASE_PATH}${normalizedPath}`;
}

const socialImage = {
  url: toCanonicalUrl("/icon.png"),
  width: 1024,
  height: 1024,
  alt: "Reframer app icon",
};

export function createPageMetadata({
  title,
  description,
  path,
}: {
  title: string;
  description: string;
  path: string;
}): Metadata {
  const url = toCanonicalUrl(path);

  return {
    title,
    description,
    alternates: { canonical: url },
    openGraph: {
      title,
      description,
      type: "website",
      url,
      siteName: SITE_NAME,
      images: [socialImage],
    },
    twitter: {
      card: "summary",
      title,
      description,
      images: [{ url: socialImage.url, alt: socialImage.alt }],
    },
  };
}

export const softwareApplicationJsonLd = {
  "@context": "https://schema.org",
  "@type": "SoftwareApplication",
  name: "Reframer",
  applicationCategory: "DesktopApplication",
  operatingSystem: "macOS 14+",
  url: toCanonicalUrl("/"),
  description:
    "A transparent video overlay for macOS. Keep reference visible while you work for animation, motion design, and tutorial breakdown workflows.",
  image: toCanonicalUrl("/icon.png"),
  author: {
    "@type": "Organization",
    name: "IVG Design",
    url: CANONICAL_HOST,
  },
  sameAs: "https://github.com/ivg-design/reframer",
  offers: {
    "@type": "Offer",
    price: "0",
    priceCurrency: "USD",
    url: "https://contra.com/products/UBCf87LD-reframer",
  },
  isAccessibleForFree: true,
};
