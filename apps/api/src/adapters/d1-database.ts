import type { SqlDatabase, SqlResult, SqlStatement } from '../core/types.js';

export class D1SqlDatabase implements SqlDatabase {
  constructor(private readonly client: D1Database) {}

  async execute<Row extends Record<string, unknown>>(statement: SqlStatement): Promise<SqlResult<Row>> {
    const result = await this.client.prepare(statement.sql).bind(...(statement.params ?? [])).all<Row>();
    return {
      rows: result.results,
      changes: result.meta.changes ?? 0,
    };
  }

  async batch(statements: SqlStatement[]): Promise<void> {
    await this.client.batch(
      statements.map((statement) =>
        this.client.prepare(statement.sql).bind(...(statement.params ?? [])),
      ),
    );
  }
}
