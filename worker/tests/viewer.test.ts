import assert from "node:assert/strict";
import test from "node:test";

import { handleViewer } from "../src/api/viewer";
import type { Env } from "../src/env";

test("viewer suppresses referrers for capability URLs", async () => {
  const response = handleViewer(
    new URL("https://share.example.test/v/Abc123.mov"),
    { R2_PUB_HOST: "media.example.test" } as Env
  );

  assert.equal(response.status, 200);
  assert.equal(response.headers.get("Referrer-Policy"), "no-referrer");
  const body = await response.text();
  assert.match(body, /<meta name="referrer" content="no-referrer">/);
  assert.match(body, /id="reportLink"/);
  assert.doesNotMatch(body, /referrerpolicy="unsafe-url"/);

  const scripts = [...body.matchAll(/<script>([\s\S]*?)<\/script>/g)];
  assert.ok(scripts.length > 0);
  for (const script of scripts) {
    assert.doesNotThrow(() => new Function(script[1]));
  }
});
