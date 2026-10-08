import { DomainError } from '../core/errors.js';
import type { StudentVerifier } from '../core/types.js';

export class DevelopmentStudentVerifier implements StudentVerifier {
  async verify(input: {
    studentId: string;
    password: string;
    claimedDepartmentId: string | null;
  }) {
    if (!/^\d{8,12}$/.test(input.studentId)) {
      throw new DomainError('invalid_student_id', '开发学号必须为 8–12 位数字');
    }
    if (input.password !== 'dev-password') {
      throw new DomainError('school_auth_failed', '学校身份验证失败', 401);
    }
    return {
      studentId: input.studentId,
      realName: '开发测试学生',
      departmentId: input.claimedDepartmentId,
    };
  }
}

export class DisabledStudentVerifier implements StudentVerifier {
  async verify(): Promise<never> {
    throw new DomainError(
      'student_verification_unavailable',
      '生产学生身份验证尚未配置，注册已关闭',
      503,
    );
  }
}
