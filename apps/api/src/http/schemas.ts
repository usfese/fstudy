import { z } from '@hono/zod-openapi';

export const ErrorSchema = z.object({
  error: z.object({ code: z.string(), message: z.string() }),
});

export const UsernameSchema = z
  .string()
  .trim()
  .regex(/^[A-Za-z0-9_]{3,20}$/);

export const RegisterSchema = z.object({
  username: UsernameSchema,
  email: z.email().max(254),
  appPassword: z.string().min(10).max(128),
  // Optional; defaults to the username. Not used for login.
  displayName: z.string().trim().min(1).max(30).optional(),
  departmentId: z.string().trim().min(1).max(64).nullable().default(null),
  inviteCode: z.string().trim().min(8).max(32),
});

export const LoginSchema = z.object({
  username: z.string().trim().min(1).max(32),
  appPassword: z.string().min(1).max(128),
});

export const ProfileSchema = z.object({
  displayName: z.string().trim().min(1).max(30),
  bio: z.string().trim().max(300),
  departmentId: z.string().trim().min(1).max(64).nullable(),
  discoverable: z.boolean(),
  scheduleVisibility: z.enum(['private', 'busy_only', 'course_name', 'full']),
});

export const CreateTagSchema = z.object({
  name: z.string().trim().min(1).max(40),
  category: z.enum(['interest', 'field', 'goal']),
});

export const UserTagsSchema = z.object({
  tags: z.array(z.object({
    tagId: z.string().min(1).max(64),
    isCore: z.boolean().default(false),
    visible: z.boolean().default(true),
    usedForRecommendation: z.boolean().default(true),
  })).max(18),
});

export const FriendRequestSchema = z.object({
  targetUserId: z.string().uuid(),
});

export const FriendRequestActionSchema = z.object({
  action: z.enum(['accept', 'reject', 'cancel']),
});

export const AvailabilityQuerySchema = z.object({
  friendId: z.string().uuid(),
  date: z.iso.date(),
  weekNumber: z.coerce.number().int().min(1).max(30),
  dayStartMinute: z.coerce.number().int().min(0).max(1439).default(480),
  dayEndMinute: z.coerce.number().int().min(1).max(1440).default(1320),
  timezoneOffsetMinutes: z.coerce.number().int().min(-840).max(840).default(480),
}).refine((value) => value.dayEndMinute > value.dayStartMinute, {
  message: '结束时间必须晚于开始时间',
});

export const AvailabilityInviteSchema = z.object({
  friendId: z.string().uuid(),
  startsAt: z.iso.datetime({ offset: true }),
  endsAt: z.iso.datetime({ offset: true }),
  title: z.string().trim().min(1).max(100),
});

export const AvailabilityInviteActionSchema = z.object({
  action: z.enum(['accept', 'reject', 'cancel']),
});

export const ProjectSchema = z.object({
  title: z.string().trim().min(1).max(100),
  description: z.string().trim().min(1).max(3000),
  capacity: z.number().int().min(1).max(50),
  tagIds: z.array(z.string().min(1).max(64)).max(8),
});

export const ProjectStatusSchema = z.object({
  status: z.enum(['recruiting', 'in_progress', 'closed']),
});

export const ProjectApplicationSchema = z.object({
  message: z.string().trim().min(1).max(500),
});

export const ProjectApplicationActionSchema = z.object({
  action: z.enum(['accept', 'reject', 'withdraw']),
});

export const ForumPostSchema = z.object({
  category: z.enum(['general', 'course', 'campus', 'experience']),
  title: z.string().trim().min(1).max(100),
  body: z.string().trim().min(1).max(5000),
});

export const ForumReplySchema = z.object({
  body: z.string().trim().min(1).max(2000),
});

export const AdminLoginSchema = z.object({
  username: z.string().trim().min(3).max(64),
  password: z.string().min(1).max(128),
});
export const AdminPasswordSchema = z.object({
  currentPassword: z.string().min(1).max(128),
  newPassword: z.string().min(14).max(128),
});

export const ContentReportSchema = z.object({
  targetType: z.enum(['forum_post', 'forum_reply', 'project']),
  targetId: z.string().min(1).max(64),
  reason: z.string().trim().min(5).max(500),
});

export const AcademicSettingsSchema = z.object({
  semesterStartDate: z.iso.date().nullable(),
});

export const NotificationReadSchema = z.object({
  id: z.string().min(1).max(64).optional(),
});

export const CasCompleteSchema = z.object({
  code: z.string().min(32).max(128),
  state: z.string().min(32).max(128),
  displayName: z.string().trim().min(1).max(30).optional(),
  appPassword: z.string().min(10).max(128).optional(),
  departmentId: z.string().trim().min(1).max(64).nullable().default(null),
});

// [2026-10-14 已停用] 验证码 / 学校密码验证相关代码，保留以便日后恢复，勿直接启用：
// export const CasPasswordChallengeSchema = z.object({
  // studentId: z.string().regex(/^\d{8,12}$/),
// });

// export const CasPasswordVerificationSchema = z.object({
  // challengeId: z.string().min(32).max(128),
  // studentId: z.string().regex(/^\d{8,12}$/),
  // schoolPassword: z.string().min(1).max(256),
  // captcha: z.string().max(32).nullable().optional(),
  // displayName: z.string().trim().min(1).max(30),
  // appPassword: z.string().min(10).max(128),
  // departmentId: z.string().trim().min(1).max(64).nullable().default(null),
// });

// export const CasPasswordRefreshSchema = z.object({
  // challengeId: z.string().min(32).max(128),
  // studentId: z.string().regex(/^\d{8,12}$/),
// });

export const AdminUserStatusSchema = z.object({ status: z.enum(['active', 'suspended']) });
export const AdminContentActionSchema = z.object({ action: z.enum(['hide', 'restore', 'delete']) });
export const AdminReportStatusSchema = z.object({ status: z.enum(['resolved', 'dismissed']) });
export const AdminTagSchema = z.object({
  id: z.string().trim().min(1).max(100).optional(),
  category: z.enum(['interest', 'field', 'goal']),
  name: z.string().trim().min(1).max(40),
  active: z.boolean().default(true),
});

export const CourseSchema = z.object({
  name: z.string().trim().min(1).max(80),
  teacher: z.string().trim().max(50).nullable().default(null),
  color: z.string().regex(/^#[0-9A-Fa-f]{6}$/).default('#4F46E5'),
  meetings: z.array(z.object({
    weekday: z.number().int().min(1).max(7),
    startMinute: z.number().int().min(0).max(1439),
    endMinute: z.number().int().min(1).max(1440),
    startWeek: z.number().int().min(1).max(30),
    endWeek: z.number().int().min(1).max(30),
    weekParity: z.enum(['all', 'odd', 'even']).default('all'),
    campus: z.string().trim().max(50).nullable().default(null),
    building: z.string().trim().max(80).nullable().default(null),
    room: z.string().trim().max(50).nullable().default(null),
  }).refine((meeting) => meeting.endMinute > meeting.startMinute, '结束时间必须晚于开始时间')
    .refine((meeting) => meeting.endWeek >= meeting.startWeek, '结束周必须不早于开始周')).min(1).max(10),
});

export const AssignmentSchema = z.object({
  courseId: z.string().uuid().nullable().default(null),
  title: z.string().trim().min(1).max(100),
  notes: z.string().trim().max(2000).default(''),
  dueAt: z.iso.datetime({ offset: true }).nullable().default(null),
});

export const CompletionSchema = z.object({ completed: z.boolean() });

export const PlanSchema = z.object({
  title: z.string().trim().min(1).max(100),
  notes: z.string().trim().max(2000).default(''),
  startsAt: z.iso.datetime({ offset: true }),
  endsAt: z.iso.datetime({ offset: true }),
  reminderMinutes: z.number().int().min(0).max(10080).nullable().default(null),
});
