import { DatabaseSync } from 'node:sqlite';
import type { SqlDatabase, SqlResult, SqlStatement } from '../core/types.js';

export class NodeSqliteDatabase implements SqlDatabase {
  private readonly client: DatabaseSync;

  constructor(filename: string) {
    this.client = new DatabaseSync(filename);
    this.client.exec('PRAGMA foreign_keys = ON; PRAGMA journal_mode = WAL;');
  }

  applyMigration(sql: string): void {
    this.client.exec(sql);
  }

  async execute<Row extends Record<string, unknown>>(statement: SqlStatement): Promise<SqlResult<Row>> {
    const prepared = this.client.prepare(statement.sql);
    const params = statement.params ?? [];
    if (/^\s*(SELECT|WITH|PRAGMA)/i.test(statement.sql)) {
      return { rows: prepared.all(...params) as Row[], changes: 0 };
    }
    const result = prepared.run(...params);
    return { rows: [], changes: Number(result.changes) };
  }

  async batch(statements: SqlStatement[]): Promise<void> {
    this.client.exec('BEGIN IMMEDIATE');
    try {
      for (const statement of statements) {
        this.client.prepare(statement.sql).run(...(statement.params ?? []));
      }
      this.client.exec('COMMIT');
    } catch (error) {
      this.client.exec('ROLLBACK');
      throw error;
    }
  }
}
