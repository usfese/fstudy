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

// [2026-10-14 已停用] 验证码 / 学校密码验证相关代码，保留以便日后恢复，勿直接启用：
// export type VerifiedStudent = {
  // studentId: string;
  // realName: string | null;
  // departmentId: string | null;
// };

// export interface StudentVerifier {
  // verify(input: {
    // studentId: string;
    // password: string;
    // claimedDepartmentId: string | null;
  // }): Promise<VerifiedStudent>;
// }

export type RuntimeDependencies = {
  database: SqlDatabase;
  studentIdPepper: string;
  clock?: () => Date;
  allowedOrigins?: string[];
  adminBootstrapUsername?: string | undefined;
  adminBootstrapPassword?: string | undefined;
  casCallbackUrl?: string | undefined;
  casLoginEnabled?: boolean;
  inviteRegistrationEnabled?: boolean;
};
