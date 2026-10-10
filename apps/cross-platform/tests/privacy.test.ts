import { test } from 'node:test'
import assert from 'node:assert/strict'
// @ts-expect-error Packaging scanner is deliberately usable directly by Node.
import { violations } from '../scripts/privacy.mjs'
test('packaging scanner finds Windows/Mac personal paths and usernames without exposing matched values', () => {
  assert.ok(violations('C:\\Users\\private-person\\source\\main.cpp', 'testuser').includes('personal filesystem path'))
  assert.ok(violations('/Users/private-person/project', 'testuser').includes('personal filesystem path'))
  assert.ok(violations('compiled by testuser', 'testuser').includes('local username'))
  assert.ok(violations('-----BEGIN PRIVATE KEY-----', 'testuser').includes('possible credential'))
  assert.deepEqual(violations('C:\\Users\\Public\\Documents /home/runner/build neutral paths', 'testuser'), [])
  assert.deepEqual(violations('reauth/v1beta/users/\0\0v1/issuetoken\0oauth2/v4/token', 'testuser'), [])
})
