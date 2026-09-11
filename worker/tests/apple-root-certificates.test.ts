import assert from "node:assert/strict";
import { createHash, X509Certificate } from "node:crypto";
import test from "node:test";

import { APPLE_ROOT_CERTIFICATES } from "../src/apple-root-certificates";

const OFFICIAL_SHA256 = [
  "b0b1730ecbc7ff4505142c49f1295e6eda6bcaed7e2c68c5be91b5a11001f024",
  "c2b9b042dd57830e7d117dac55ac8ae19407d38e41d88f3215bc3a890444a050",
  "63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179",
];

test("Apple verifier trust anchors match the current official root set", () => {
  const hashes = APPLE_ROOT_CERTIFICATES.map((certificate) =>
    createHash("sha256").update(certificate).digest("hex")
  );
  assert.deepEqual(hashes, OFFICIAL_SHA256);

  const commonNames = APPLE_ROOT_CERTIFICATES.map((certificate) =>
    new X509Certificate(certificate).subject
  );
  assert.match(commonNames[0]!, /CN=Apple Root CA/);
  assert.match(commonNames[1]!, /CN=Apple Root CA - G2/);
  assert.match(commonNames[2]!, /CN=Apple Root CA - G3/);
});
