// Two kinds of build:
//   npm run build                     -> the public site: published guides only
//   SITE_MODE=preview npm run build   -> drafts included, every page noindex,
//                                        robots.txt disallows everything
// The dev server always shows drafts.
export const isPreview = import.meta.env.DEV || process.env.SITE_MODE === 'preview';
