// cloudshare token gate.
// Validates ?token=<x> against SHARE_TOKENS_JSON env var, keyed by /r/<slug>/.

export async function onRequest(context) {
  const url = new URL(context.request.url);
  const path = url.pathname;

  // Allow root + obvious benign paths so the landing page renders publicly.
  if (path === '/' || path === '/index.html' || path === '/favicon.ico' || path === '/robots.txt') {
    return context.next();
  }

  // Only /r/<slug>/... is gated. Anything else: 404.
  const m = path.match(/^\/r\/([^/]+)(\/.*)?$/);
  if (!m) {
    return new Response('Not Found', { status: 404 });
  }

  const slug = m[1];
  let tokens = {};
  try {
    tokens = JSON.parse(context.env.SHARE_TOKENS_JSON || '{}');
  } catch (e) {
    return new Response('Server misconfiguration', { status: 500 });
  }

  const expected = tokens[slug];
  if (!expected) {
    return new Response('Not Found', { status: 404 });
  }

  const provided = url.searchParams.get('token');
  if (provided !== expected) {
    return new Response('Unauthorized — link requires a valid token.', {
      status: 401,
      headers: { 'Content-Type': 'text/plain; charset=utf-8' },
    });
  }

  return context.next();
}
