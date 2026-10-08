import type { SqlDatabase } from '../../core/types.js';

type CandidateRow = {
  id: string;
  display_name: string;
  department_id: string | null;
  bio: string;
  same_department: number;
  common_tag_count: number;
  relationship: 'none' | 'outgoing' | 'incoming' | 'friends';
};

type VisibleTagRow = {
  user_id: string;
  id: string;
  category: 'interest' | 'field' | 'goal';
  name: string;
  is_core: number;
  common: number;
};

export class DiscoveryService {
  constructor(private readonly database: SqlDatabase) {}

  async discover(userId: string) {
    const candidates = await this.database.execute<CandidateRow>({
      sql: `SELECT u.id, u.display_name, u.department_id, u.bio,
              CASE WHEN u.department_id IS NOT NULL AND u.department_id = me.department_id THEN 1 ELSE 0 END AS same_department,
              COUNT(DISTINCT CASE
                WHEN mine.used_for_recommendation = 1 AND theirs.used_for_recommendation = 1
                THEN theirs.tag_id END) AS common_tag_count,
              CASE
                WHEN f.pair_key IS NOT NULL THEN 'friends'
                WHEN r.status = 'pending' AND r.sender_id = ? THEN 'outgoing'
                WHEN r.status = 'pending' AND r.receiver_id = ? THEN 'incoming'
                ELSE 'none'
              END AS relationship
            FROM users u
            JOIN users me ON me.id = ?
            LEFT JOIN user_tags theirs ON theirs.user_id = u.id
            LEFT JOIN user_tags mine ON mine.user_id = ? AND mine.tag_id = theirs.tag_id
            LEFT JOIN friendships f ON f.pair_key = CASE
              WHEN ? < u.id THEN ? || ':' || u.id ELSE u.id || ':' || ? END
            LEFT JOIN friend_requests r ON r.pair_key = CASE
              WHEN ? < u.id THEN ? || ':' || u.id ELSE u.id || ':' || ? END
            WHERE u.id <> ? AND u.status = 'active' AND u.discoverable = 1
            GROUP BY u.id, u.display_name, u.department_id, u.bio, me.department_id,
                     f.pair_key, r.status, r.sender_id, r.receiver_id
            ORDER BY common_tag_count DESC, same_department DESC, u.display_name
            LIMIT 50`,
      params: [
        userId, userId, userId, userId, userId, userId,
        userId, userId, userId, userId, userId,
      ],
    });
    if (candidates.rows.length === 0) return [];

    const placeholders = candidates.rows.map(() => '?').join(',');
    const tags = await this.database.execute<VisibleTagRow>({
      sql: `SELECT ut.user_id, t.id, t.category, t.name, ut.is_core,
              CASE WHEN mine.tag_id IS NULL THEN 0 ELSE 1 END AS common
            FROM user_tags ut
            JOIN tags t ON t.id = ut.tag_id AND t.active = 1
            LEFT JOIN user_tags mine ON mine.user_id = ? AND mine.tag_id = ut.tag_id
              AND mine.used_for_recommendation = 1 AND ut.used_for_recommendation = 1
            WHERE ut.visible = 1 AND ut.user_id IN (${placeholders})
            ORDER BY ut.is_core DESC, t.category, t.name`,
      params: [userId, ...candidates.rows.map((row) => row.id)],
    });

    return candidates.rows.map((candidate) => ({
      id: candidate.id,
      displayName: candidate.display_name,
      departmentId: candidate.department_id,
      bio: candidate.bio,
      sameDepartment: candidate.same_department === 1,
      commonTagCount: candidate.common_tag_count,
      relationship: candidate.relationship,
      tags: tags.rows.filter((tag) => tag.user_id === candidate.id).map((tag) => ({
        id: tag.id,
        category: tag.category,
        name: tag.name,
        isCore: tag.is_core === 1,
        common: tag.common === 1,
      })),
    }));
  }
}
