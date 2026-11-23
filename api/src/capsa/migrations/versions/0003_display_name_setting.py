"""display name as a synced setting

The display name moves from users.display_name into user_settings (key
'display_name'), so devices can change it offline and sync it like any setting.

Revision ID: 0003
Revises: 0002
"""

import json

import sqlalchemy as sa
from alembic import op

revision = "0003"
down_revision = "0002"
branch_labels = None
depends_on = None


def upgrade() -> None:
    conn = op.get_bind()
    rows = conn.execute(
        sa.text("SELECT id, display_name, updated_at FROM users WHERE display_name IS NOT NULL")
    ).all()
    for user_id, name, updated_at in rows:
        conn.execute(
            sa.text(
                "INSERT INTO user_settings (user_id, key, value, updated_at) "
                "VALUES (:user_id, 'display_name', :value, :updated_at)"
            ),
            {
                "user_id": user_id,
                "value": json.dumps(name, ensure_ascii=False),
                "updated_at": updated_at,
            },
        )
    with op.batch_alter_table("users", schema=None) as batch_op:
        batch_op.drop_column("display_name")


def downgrade() -> None:
    with op.batch_alter_table("users", schema=None) as batch_op:
        batch_op.add_column(sa.Column("display_name", sa.String(length=64), nullable=True))
    conn = op.get_bind()
    rows = conn.execute(
        sa.text("SELECT user_id, value FROM user_settings WHERE key = 'display_name'")
    ).all()
    for user_id, value in rows:
        conn.execute(
            sa.text("UPDATE users SET display_name = :name WHERE id = :id"),
            {"name": json.loads(value), "id": user_id},
        )
    conn.execute(sa.text("DELETE FROM user_settings WHERE key = 'display_name'"))
