'use strict';

// Firebase entry point. The logic lives in handler.js and preview.js so
// it can be tested without the Firebase SDK; see docs/link-previews.md.

const { onRequest } = require('firebase-functions/v2/https');
const { makeHandler } = require('./handler');

exports.linkPreview = onRequest(
  {
    // Singapore: closest region to the college. Must match the region in
    // the firebase.json rewrite.
    region: 'asia-southeast1',
    memory: '256MiB',
    // Concurrency above 1 needs a whole vCPU; billed only while serving.
    cpu: 1,
    timeoutSeconds: 15,
    // Hard ceiling on cost if a link is ever hammered: at most this many
    // instances, each handling many requests at once.
    maxInstances: 3,
    concurrency: 40,
  },
  makeHandler(),
);
