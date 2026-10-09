"""Run against disposable normal/maintenance proxies and a disconnected edge proxy."""
import argparse
import json
import re
from urllib.request import urlopen
from urllib.error import HTTPError

parser = argparse.ArgumentParser()
parser.add_argument('--normal-url', default='http://127.0.0.1:5183')
parser.add_argument('--maintenance-url', default='http://127.0.0.1:5184')
parser.add_argument('--edge-url', default='http://127.0.0.1:5185')
args = parser.parse_args()

def get(base, path):
    try:
        response = urlopen(base + path, timeout=10)
    except HTTPError as error:
        response = error
    return response.status, response.headers, response.read().decode()

for path in ['/products/1/wiki', '/unknown-link']:
    status, headers, body = get(args.normal_url, path)
    assert status == 200 and 'id="root"' in body, (path, status)
status, headers, body = get(args.normal_url, '/')
asset = re.search(r'src="(/assets/[^\"]+\.js)"', body)
assert asset, 'Production JavaScript asset not found in index.html'
status, headers, body = get(args.normal_url, asset.group(1))
assert status == 200
assert headers.get('Cache-Control') == 'public, max-age=31536000, immutable'
for path, content_type, cache_control in [
    ('/sw.js', 'application/javascript', 'no-store'),
    ('/manifest.webmanifest', 'application/manifest+json', 'no-cache'),
]:
    status, headers, body = get(args.normal_url, path)
    assert status == 200, (path, status)
    assert content_type in headers.get('Content-Type', ''), (path, headers)
    assert headers.get('Cache-Control') == cache_control, (path, headers)
    assert headers.get('CDN-Cache-Control') == 'no-store', (path, headers)
    assert headers.get('Cloudflare-CDN-Cache-Control') == 'no-store', (path, headers)
for path in ['/missing.png', '/assets/missing.js']:
    status, headers, body = get(args.normal_url, path)
    assert status == 404 and 'id="root"' not in body, (path, status)
for base in [args.normal_url, args.maintenance_url]:
    assert get(base, '/healthz')[0] == 200
for base in [args.maintenance_url, args.edge_url]:
    for path in ['/products/1/wiki', '/index.html']:
        status, headers, body = get(base, path)
        assert status == 503 and 'FreshPrice' in body, (base, path, status)
        assert headers.get('Retry-After') == '60'
        assert headers.get('Cache-Control') == 'no-store'
for base in [args.normal_url, args.maintenance_url, args.edge_url]:
    status, headers, body = get(base, '/api/platform/db/health')
    assert status == 503 and 'application/json' in headers.get('Content-Type', '')
    assert json.loads(body)['message'] == 'Service temporarily unavailable'
    assert headers.get('Cache-Control') == 'no-store'
print('Maintenance, edge fallback, deep-link, asset and API checks passed.')
