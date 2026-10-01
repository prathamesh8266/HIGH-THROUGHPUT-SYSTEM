import http from 'k6/http';
import { check } from 'k6';

const method = __ENV.METHOD || 'GET';
const baseUrl = (__ENV.BASE_URL || 'http://localhost:8080').replace(/\/$/, '');
const url = __ENV.URL || (method === 'POST' ? `${baseUrl}/dp` : `${baseUrl}/db`);
const timeout = __ENV.REQUEST_TIMEOUT || '100s';
const testType = __ENV.TEST_TYPE || 'load';

// Edit stage durations and VU targets here, not in .env.
const profiles = {
  load: [
    { duration: '30s', target: 1000 },
    { duration: '1m', target: 1000 },
    { duration: '30s', target: 0 },
  ],
  stress: [
    { duration: '30s', target: 1000 },
    { duration: '30s', target: 1000 },
    { duration: '30s', target: 2500 },
    { duration: '30s', target: 2500 },
    { duration: '30s', target: 5000 },
    { duration: '30s', target: 5000 },
    { duration: '30s', target: 0 },
  ],
  spike: [
    { duration: '10s', target: 100 },
    { duration: '20s', target: 100 },
    { duration: '1s', target: 5000 },
    { duration: '10s', target: 5000 },
    { duration: '1s', target: 100 },
    { duration: '30s', target: 100 },
    { duration: '10s', target: 0 },
  ],
};

if (!['load', 'stress', 'spike'].includes(testType)) {
  throw new Error('TEST_TYPE must be load, stress, or spike');
}

if (!['GET', 'POST'].includes(method)) {
  throw new Error('METHOD must be GET or POST');
}

export const options = {
  vus: 1,
  stages: profiles[testType],
  tags: { test_type: testType, operation: method === 'POST' ? 'write' : 'read' },
  discardResponseBodies: true,
  summaryTrendStats: ['avg', 'min', 'med', 'max', 'p(95)', 'p(99)'],
  thresholds: {
    http_req_failed: ['rate==0'],
    checks: ['rate==1'],
    http_reqs: ['count>0'],
  },
};

// Treat any 2xx response as an HTTP success.
http.setResponseCallback(http.expectedStatuses({ min: 200, max: 299 }));

export default function () {
  const response = http.request(method, url, null, { timeout, redirects: 0 });
  check(response, { 
    'status is 200': (res) => res.status == 200, 
  });
}
