export type SqlPrimitive = string | number | null;

export type SqlStatement = {
  sql: string;
  params?: SqlPrimitive[];
};

export type SqlResult<Row extends Record<string, unknown> = Record<string, unknown>> = {
  rows: Row[];
  changes: number;
};

export interface SqlDatabase {
  execute<Row extends Record<string, unknown> = Record<string, unknown>>(
    statement: SqlStatement,
  ): Promise<SqlResult<Row>>;
  batch(statements: SqlStatement[]): Promise<void>;
}

export type VerifiedStudent = {
  studentId: string;
  realName: string | null;
  departmentId: string | null;
};

export interface StudentVerifier {
  verify(input: {
    studentId: string;
    password: string;
    claimedDepartmentId: string | null;
  }): Promise<VerifiedStudent>;
}

export type RuntimeDependencies = {
  database: SqlDatabase;
  studentVerifier: StudentVerifier;
  studentIdPepper: string;
  clock?: () => Date;
  allowedOrigins?: string[];
  adminBootstrapUsername?: string | undefined;
  adminBootstrapPassword?: string | undefined;
};
