# Reframer website

Public product site and documentation at https://forge.mograph.life/apps/reframer/. This package is independent of the native macOS application at the repository root.

## Build

Run from this directory:

```sh
npm ci
NEXT_PUBLIC_SITE_URL=https://forge.mograph.life/apps/reframer npm run build
```

The prebuild script verifies the source image hashes and generates responsive WebP assets. The Next build generates the documentation, canonical metadata and sitemap. Fonts, licenses and source image masters are included. Large demonstration videos use the existing public Vercel Blob store.

## Deployment

Vercel project: `reframer` (`prj_5Mv9NC3uQTogv4VMCqZgeDr2eK03`). The project currently uses explicit deployment and promotion; importing this package does not connect Git deployment or publish a native app. Run deployment commands from `web/`. If Git deployment is introduced, its root must be `web`, and native-only commits should not unnecessarily rebuild the site. The Forge gateway supplies the public `/apps/reframer` prefix.

## Public beta content boundary

This import preserves the deployed website source at standalone commit `50d28110074b24e00a51a8e13d13e42b98c9b893`; every imported source byte is retained except Finder `.DS_Store`. Its four-commit history is preserved separately in the verified source bundle.

The site describes the existing 0.8.1-beta.3 public beta and links to https://contra.com/products/UBCf87LD-reframer. The Contra listing was checked on September 14, 2026 and still offers a free beta; it does not expose the downloaded binary version in its public description. The native repository's 0.11.0 build is marked unreleased. Do not mechanically relabel website OS requirements, features or release notes from native main. Before the next product launch, verify the actual distributed artifact and update the public documentation together. This source import is not evidence of a new product release.
