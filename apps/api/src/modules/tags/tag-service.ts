import { DomainError } from '../../core/errors.js';
import type { SqlDatabase } from '../../core/types.js';

export type Tag = {
  id: string;
  category: 'interest' | 'field' | 'goal';
  name: string;
};

type TagRow = { id: string; category: Tag['category']; name: string };
type UserTagRow = TagRow & {
  is_core: number;
  visible: number;
  used_for_recommendation: number;
};

export type UserTag = Tag & {
  isCore: boolean;
  visible: boolean;
  usedForRecommendation: boolean;
};

export class TagService {
  constructor(private readonly database: SqlDatabase) {}

  async list(): Promise<Tag[]> {
    const result = await this.database.execute<TagRow>({
      sql: 'SELECT id, category, name FROM tags WHERE active = 1 ORDER BY category, name',
    });
    return result.rows;
  }

  async listUserTags(userId: string): Promise<UserTag[]> {
    const result = await this.database.execute<UserTagRow>({
      sql: `SELECT t.id, t.category, t.name, ut.is_core, ut.visible, ut.used_for_recommendation
            FROM user_tags ut JOIN tags t ON t.id = ut.tag_id
            WHERE ut.user_id = ? AND t.active = 1
            ORDER BY t.category, t.name`,
      params: [userId],
    });
    return result.rows.map((row) => ({
      id: row.id,
      category: row.category,
      name: row.name,
      isCore: row.is_core === 1,
      visible: row.visible === 1,
      usedForRecommendation: row.used_for_recommendation === 1,
    }));
  }

  async replaceUserTags(
    userId: string,
    selected: Array<{ tagId: string; isCore: boolean; visible: boolean; usedForRecommendation: boolean }>,
  ): Promise<void> {
    if (selected.length > 18) throw new DomainError('too_many_tags', '最多选择 18 个标签');
    if (new Set(selected.map((item) => item.tagId)).size !== selected.length) {
      throw new DomainError('duplicate_tags', '标签不能重复');
    }
    if (selected.length > 0) {
      const placeholders = selected.map(() => '?').join(',');
      const existing = await this.database.execute<{ id: string }>({
        sql: `SELECT id FROM tags WHERE active = 1 AND id IN (${placeholders})`,
        params: selected.map((item) => item.tagId),
      });
      if (existing.rows.length !== selected.length) {
        throw new DomainError('unknown_tag', '包含不存在或已停用的标签');
      }
    }
    await this.database.batch([
      { sql: 'DELETE FROM user_tags WHERE user_id = ?', params: [userId] },
      ...selected.map((item) => ({
        sql: `INSERT INTO user_tags
          (user_id, tag_id, is_core, visible, used_for_recommendation) VALUES (?, ?, ?, ?, ?)`,
        params: [
          userId,
          item.tagId,
          item.isCore ? 1 : 0,
          item.visible ? 1 : 0,
          item.usedForRecommendation ? 1 : 0,
        ],
      })),
    ]);
  }
}
