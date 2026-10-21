// Run with: node --test tests/deploy-maintenance.test.mjs
// Requires Bash and the Docker CLI only; no daemon or production connection.
// On Windows set DEPLOY_TEST_SHELL to the Git Bash executable.
import assert from "node:assert/strict"
import { execFileSync } from "node:child_process"
import { copyFileSync, mkdtempSync, readFileSync, rmdirSync, unlinkSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import test from "node:test"

const workflow = readFileSync(new URL("../.github/workflows/deploy.yml", import.meta.url), "utf8").replace(/\r\n/g, "\n")
const parser = workflow.match(/^ {12}env_value\(\) \{[\s\S]*?^ {12}done$/m)?.[0].replace(/^ {12}/gm, "")
assert.ok(parser, "Deployment environment parser not found in workflow")
const keys = parser.match(/for key in([\s\S]*?)\n\s*do/)[1].match(/[A-Z][A-Z_]+/g)

for (const setting of ["true", "false", undefined]) {
  test(`stack rendering preserves maintenance=${setting ?? "default false"}`, () => {
    const directory = mkdtempSync(join(tmpdir(), "fp64-deploy-test-"))
    const composePath = join(directory, "docker-compose.prod.yml")
    const envPath = join(directory, ".env")
    try {
      copyFileSync(new URL("../docker-compose.prod.yml", import.meta.url), composePath)
      const values = {
        DATABASE_URL: "postgres://review:review@postgres:5432/review_test",
        POSTGRES_USER: "review", POSTGRES_PASSWORD: "review", POSTGRES_DB: "review_test",
        POSTGRES_HOST: "postgres", POSTGRES_PORT: "5432",
        JWT_SECRET: "synthetic-review-only", ALLOWED_ORIGINS: "http://example.test",
        ...(setting === undefined ? {} : { FRESHPRICE_MAINTENANCE: setting }),
      }
      writeFileSync(envPath, Object.entries(values).map(([key, value]) => `${key}=${value}`).join("\n") + "\n")
      const environment = { ...process.env }
      for (const key of [...keys, "FRESHPRICE_MAINTENANCE", "BASH_ENV"]) delete environment[key]
      // Execute the workflow's actual parser rather than recreating its logic.
      const rendered = execFileSync(process.env.DEPLOY_TEST_SHELL || "bash", ["-c", `set -eu\n${parser}\ndocker stack config --compose-file docker-compose.prod.yml`], {
        cwd: directory, env: environment, encoding: "utf8", timeout: 20000, windowsHide: true,
      })
      const frontend = rendered.match(/^  frontend:\r?\n([\s\S]*?)(?=^  \w+:|^networks:)/m)?.[1]
      assert.ok(frontend, "Frontend service missing from rendered stack")
      assert.match(frontend, new RegExp(`FRESHPRICE_MAINTENANCE: "${setting ?? "false"}"`))
      const postgres = rendered.match(/^  postgres:\r?\n([\s\S]*?)(?=^  \w+:|^networks:)/m)?.[1]
      assert.ok(postgres, "PostgreSQL service missing from rendered stack")
      assert.doesNotMatch(postgres, /^    ports:/m, "Production PostgreSQL must not publish host ports")
    } finally {
      for (const file of [composePath, envPath]) {
        try { unlinkSync(file) } catch (error) { if (error.code !== "ENOENT") throw error }
      }
      rmdirSync(directory)
    }
  })
}
