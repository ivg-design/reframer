// Base path for the app - matches Next.js assetPrefix
export const basePath = '/apps/reframer';

// Check if we're in development mode or on the direct domain
const isDev = process.env.NODE_ENV === 'development';
const isDirectAccess = process.env.NEXT_PUBLIC_SITE_URL?.includes('reframer') && !process.env.NEXT_PUBLIC_SITE_URL?.includes('forge');

export function asset(path: string): string {
  // No prefix in dev mode or when accessing directly (not via forge rewrite)
  if (isDev || isDirectAccess) {
    return path;
  }
  return `${basePath}${path}`;
}

export function apiPath(path: string): string {
  // No prefix in dev mode or when accessing directly (not via forge rewrite)
  if (isDev || isDirectAccess) {
    return path;
  }
  return `${basePath}${path}`;
}

// Large media (demo video, full-size screenshots) lives in the shared Vercel Blob store
// "site-media" so it is not bundled into every deployment. Upload with: vercel blob put <file> --pathname reframer/<path>
export const MEDIA_BASE = 'https://uitihmj6x17wjfgb.public.blob.vercel-storage.com/reframer';
export function media(path: string): string {
  return `${MEDIA_BASE}${path.startsWith('/') ? path : `/${path}`}`;
}
